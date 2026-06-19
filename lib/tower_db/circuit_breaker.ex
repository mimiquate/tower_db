defmodule TowerDB.CircuitBreaker do
  @moduledoc """
  Circuit breaker pattern implementation for TowerDB database operations.

  Prevents cascade failures by:
  - Tracking database operation failures
  - Opening the circuit after threshold failures (stops attempting DB operations)
  - Queuing event batches in ETS while circuit is open
  - Periodically testing recovery with half-open state
  - Processing queued batches once database recovers

  ## States

  - `:closed` - Normal operation, batches go to database
  - `:open` - Database failing, batches queued in ETS
  - `:half_open` - Testing if database recovered

  ## Configuration

      config :tower_db, :circuit_breaker,
        failure_threshold: 3,           # consecutive failures before opening circuit
        recovery_timeout: 5_000,        # ms before attempting recovery
        queue_retry_interval: 100,      # ms between processing queued batches
        max_queue_size: 20              # max queued batches (configured in Storage)
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
  Execute a batch database operation through the circuit breaker (non-blocking).

  - In closed state: executes the function directly, queues batch on failure
  - In open state: queues the batch for later retry
  - In half-open state: tests with the batch operation, then decides
  """
  def call_batch(attrs_list, fun) when is_list(attrs_list) and is_function(fun, 0) do
    GenServer.cast(__MODULE__, {:call_batch, attrs_list, fun})
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

  @doc """
  Check if the circuit breaker can accept new batches.
  Returns true if circuit is closed OR (circuit is open/half-open AND queue has space).
  """
  def can_accept? do
    cb_state = state()
    queue_stats = Storage.state()

    case cb_state.state do
      :closed ->
        true

      _open_or_half_open ->
        # Accept if queue has space (leave some buffer room)
        queue_stats.batch_count < queue_stats.max_batch_count
    end
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    {:ok, %{state: :closed, failure_count: 0, recovery_timer_ref: nil, inserted_count: 0}}
  end

  @impl true
  def handle_cast({:call_batch, attrs_list, fun}, %{state: :closed} = state) do
    case execute(fun) do
      {:ok, _result} ->
        {:noreply, reset_failures(state)}

      {:error, reason} ->
        new_state = record_failure(state)
        Logger.warning("[CircuitBreaker] Database operation failed: #{inspect(reason)}")
        queue_batch(attrs_list)
        {:noreply, new_state}
    end
  end

  @impl true
  def handle_cast({:call_batch, attrs_list, _fun}, %{state: :open} = state) do
    case queue_batch(attrs_list) do
      :ok ->
        {:noreply, state}

      :dropped ->
        Logger.warning("[CircuitBreaker] Batch dropped - queue full")
        {:noreply, state}
    end
  end

  @impl true
  def handle_cast({:call_batch, attrs_list, fun}, %{state: :half_open} = state) do
    case execute(fun) do
      {:ok, _result} ->
        Logger.info("[CircuitBreaker] Database recovered, closing circuit")
        new_state = close_circuit(state)
        schedule_queue_processing()
        {:noreply, new_state}

      {:error, reason} ->
        Logger.warning("[CircuitBreaker] Recovery test failed: #{inspect(reason)}")
        queue_batch(attrs_list)
        {:noreply, open_circuit(state)}
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
    Logger.info("[CircuitBreaker] Transitioning to half-open state")
    new_state = half_open_circuit(state)

    # If there are queued batches, test recovery immediately with one
    case Storage.dequeue() do
      :empty ->
        # No queued batches, wait for next call_batch to test
        Logger.info("[CircuitBreaker] No queued batches, waiting for next request to test recovery")
        {:noreply, new_state}

      {:ok, attrs_list} ->
        case execute(fn -> TowerDB.Events.create_events_batch(attrs_list) end) do
          {:ok, events} ->
            Logger.info("[CircuitBreaker] Recovery successful, closing circuit")
            schedule_queue_processing()
            closed_state = close_circuit(new_state)
            {:noreply, %{closed_state | inserted_count: closed_state.inserted_count + length(events)}}

          {:error, reason} ->
            Logger.warning("[CircuitBreaker] Recovery test failed: #{inspect(reason)}")
            Storage.requeue(attrs_list)
            {:noreply, open_circuit(new_state)}
        end
    end
  end

  @impl true
  def handle_info(:try_recovery, state), do: {:noreply, state}

  @impl true
  def handle_info(:process_queue, %{state: :closed} = state) do
    {:noreply, process_queued_batches(state)}
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

  defp reset_failures(state) do
    if Storage.queue_size() > 0 do
      schedule_queue_processing()
    end

    %{state | failure_count: 0}
  end

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

  defp half_open_circuit(state) do
    cancel_timer(state.recovery_timer_ref)
    %{state | state: :half_open, recovery_timer_ref: nil}
  end

  defp cancel_timer(nil), do: :ok
  defp cancel_timer(ref), do: Process.cancel_timer(ref)

  defp queue_batch(attrs_list) do
    filtered = Enum.reject(attrs_list, &skip_event?/1)

    if Enum.empty?(filtered) do
      Logger.debug("[CircuitBreaker] All events filtered - not queuing batch")
      :ok
    else
      Logger.info("[CircuitBreaker] Batch enqueue (#{length(filtered)} events)")
      Storage.enqueue(filtered)
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

  defp process_queued_batches(state) do
    case Storage.dequeue() do
      :empty ->
        log_processing_summary(state.inserted_count)
        %{state | inserted_count: 0}

      {:ok, attrs_list} ->
        case execute(fn -> TowerDB.Events.create_events_batch(attrs_list) end) do
          {:ok, events} ->
            Logger.info("[CircuitBreaker] Queued batch inserted (#{length(events)} events)")
            schedule_queue_processing()
            %{state | inserted_count: state.inserted_count + length(events)}

          {:error, _reason} ->
            Logger.warning("[CircuitBreaker] Queue processing failed, re-opening circuit")
            Storage.requeue(attrs_list)
            open_circuit(state)
        end
    end
  end

  defp log_processing_summary(inserted_count) do
    stats = Storage.state()

    Logger.info(
      "[CircuitBreaker] Queue processing complete: " <>
      "#{inserted_count} events inserted, " <>
      "#{stats.events_dropped} events dropped"
    )
  end

  defp config(key, default) do
    Application.get_env(:tower_db, :circuit_breaker, [])
    |> Keyword.get(key, default)
  end
end
