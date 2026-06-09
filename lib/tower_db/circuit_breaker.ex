defmodule TowerDB.CircuitBreaker do
  @moduledoc """
  Circuit breaker pattern implementation for TowerDB database operations.

  Prevents cascade failures by:
  - Tracking database operation failures
  - Opening the circuit after threshold failures (stops attempting DB operations)
  - Queuing events in ETS while circuit is open
  - Periodically testing recovery with half-open state
  - Processing queued events once database recovers

  ## States

  - `:closed` - Normal operation, events go to database
  - `:open` - Database failing, events queued in ETS
  - `:half_open` - Testing if database recovered

  ## Configuration

      config :tower_db, :circuit_breaker,
        failure_threshold: 3,           # consecutive failures before opening circuit
        recovery_timeout: 5_000,        # ms before attempting recovery
        queue_retry_interval: 100,      # ms between processing queued events
        max_queue_size: 1000            # max queued events (configured in Storage)
  """

  use GenServer

  require Logger

  alias TowerDB.CircuitBreaker.Storage

  @default_failure_threshold 3
  @default_recovery_timeout 5_000
  @default_queue_retry_interval 100

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Execute a database operation through the circuit breaker.

  - In closed state: executes the function directly, queues on failure
  - In open state: queues the event for later retry
  - In half-open state: tests with one operation, then decides
  """
  def call(attrs, fun) when is_function(fun, 0) do
    GenServer.call(__MODULE__, {:call, attrs, fun})
  end

  @doc """
  Get the current circuit breaker state.
  """
  def state do
    GenServer.call(__MODULE__, :state)
  end

  @doc """
  Manually reset the circuit breaker to closed state.
  """
  def reset do
    GenServer.call(__MODULE__, :reset)
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    {:ok, %{state: :closed, failure_count: 0, recovery_timer_ref: nil, inserted_count: 0}}
  end

  @impl true
  def handle_call({:call, attrs, fun}, _from, %{state: :closed} = state) do
    case execute(fun) do
      {:ok, result} ->
        {:reply, {:ok, result}, reset_failures(state)}

      {:error, reason} = error ->
        new_state = record_failure(state)
        Logger.warning("[CircuitBreaker] Database operation failed: #{inspect(reason)}")
        queue_event(attrs)
        {:reply, error, new_state}
    end
  end

  @impl true
  def handle_call({:call, attrs, _fun}, _from, %{state: :open} = state) do
    case queue_event(attrs) do
      :ok ->
        {:reply, {:queued, :circuit_open}, state}

      :dropped ->
        Logger.warning("[CircuitBreaker] Event dropped - queue full")
        {:reply, {:dropped, :queue_full}, state}
    end
  end

  @impl true
  def handle_call({:call, attrs, fun}, _from, %{state: :half_open} = state) do
    case execute(fun) do
      {:ok, result} ->
        Logger.info("[CircuitBreaker] Database recovered, closing circuit")
        new_state = close_circuit(state)
        schedule_queue_processing()
        {:reply, {:ok, result}, new_state}

      {:error, reason} = error ->
        Logger.warning("[CircuitBreaker] Recovery test failed: #{inspect(reason)}")
        queue_event(attrs)
        {:reply, error, open_circuit(state)}
    end
  end

  @impl true
  def handle_call(:state, _from, state) do
    {:reply, %{
      state: state.state,
      failure_count: state.failure_count,
      queue_size: Storage.queue_size()
    }, state}
  end

  @impl true
  def handle_call(:reset, _from, state) do
    cancel_timer(state.recovery_timer_ref)
    {:reply, :ok, %{state | state: :closed, failure_count: 0, recovery_timer_ref: nil}}
  end

  @impl true
  def handle_info(:try_recovery, %{state: :open} = state) do
    Logger.info("[CircuitBreaker] Attempting recovery (half-open)")

    case Storage.dequeue() do
      :empty ->
        Logger.info("[CircuitBreaker] No queued events, closing circuit")
        {:noreply, close_circuit(state)}

      {:ok, attrs} ->
        case execute(fn -> TowerDB.Events.create_event(attrs) end) do
          {:ok, _event} ->
            Logger.info("[CircuitBreaker] Recovery successful, closing circuit")
            schedule_queue_processing()
            new_state = close_circuit(state)
            {:noreply, %{new_state | inserted_count: new_state.inserted_count + 1}}

          {:error, reason} ->
            Logger.warning("[CircuitBreaker] Recovery test failed: #{inspect(reason)}")
            Storage.requeue(attrs)
            {:noreply, open_circuit(state)}
        end
    end
  end

  @impl true
  def handle_info(:try_recovery, state), do: {:noreply, state}

  @impl true
  def handle_info(:process_queue, %{state: :closed} = state) do
    {:noreply, process_queued_events(state)}
  end

  @impl true
  def handle_info(:process_queue, state), do: {:noreply, state}

  # Private Functions

  defp execute(fun) do
    case fun.() do
      {:ok, _} = success -> success
      {:error, _} = error -> error
      other -> {:ok, other}
    end
  rescue
    e -> {:error, e}
  catch
    :exit, reason -> {:error, {:exit, reason}}
  end

  defp record_failure(state) do
    count = state.failure_count + 1
    threshold = config(:failure_threshold, @default_failure_threshold)

    if count >= threshold do
      Logger.warning("[CircuitBreaker] Threshold reached, opening circuit")
      open_circuit(%{state | failure_count: count})
    else
      %{state | failure_count: count}
    end
  end

  defp reset_failures(state), do: %{state | failure_count: 0}

  defp open_circuit(state) do
    cancel_timer(state.recovery_timer_ref)
    timeout = config(:recovery_timeout, @default_recovery_timeout)
    ref = Process.send_after(self(), :try_recovery, timeout)
    %{state | state: :open, recovery_timer_ref: ref}
  end

  defp close_circuit(state) do
    cancel_timer(state.recovery_timer_ref)
    %{state | state: :closed, failure_count: 0, recovery_timer_ref: nil}
  end

  defp cancel_timer(nil), do: :ok
  defp cancel_timer(ref), do: Process.cancel_timer(ref)

  defp queue_event(attrs) do
    if skip_event?(attrs) do
      Logger.debug("[CircuitBreaker] Filtering event - not queuing")
      :ok
    else
      Storage.enqueue(attrs)
    end
  end

  # Filter Tower reporter errors (prevents infinite loop when reporter fails)
  defp skip_event?(%{reason: %Tower.ReportEventError{}}), do: true
  # Filter DB-related errors (not useful to store when DB recovers)
  defp skip_event?(%{reason: reason}) do
    reason_str = reason |> inspect() |> String.downcase()

    Enum.any?(~w(dbconnection postgrex econnrefused ecto.adapters.sql), fn pattern ->
      String.contains?(reason_str, pattern)
    end)
  end
  defp skip_event?(_), do: false

  defp schedule_queue_processing do
    interval = config(:queue_retry_interval, @default_queue_retry_interval)
    Process.send_after(self(), :process_queue, interval)
  end

  defp process_queued_events(state) do
    case Storage.dequeue() do
      :empty ->
        log_processing_summary(state.inserted_count)
        %{state | inserted_count: 0}

      {:ok, attrs} ->
        case execute(fn -> TowerDB.Events.create_event(attrs) end) do
          {:ok, event} ->
            Logger.info("[CircuitBreaker] Queued event #{event.id} inserted")
            schedule_queue_processing()
            %{state | inserted_count: state.inserted_count + 1}

          {:error, _reason} ->
            Logger.warning("[CircuitBreaker] Queue processing failed, re-opening circuit")
            Storage.requeue(attrs)
            open_circuit(state)
        end
    end
  end

  defp log_processing_summary(inserted_count) do
    stats = Storage.state()

    Logger.info(
      "[CircuitBreaker] Queue processing complete: " <>
      "#{inserted_count} events inserted, " <>
      "#{stats.total_dropped} events dropped (queue was full)"
    )
  end

  defp config(key, default) do
    Application.get_env(:tower_db, :circuit_breaker, [])
    |> Keyword.get(key, default)
  end
end
