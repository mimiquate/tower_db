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
        queue_retry_attempts: 3,        # retries when processing queued events
        queue_retry_delay: 1_000,       # ms between retries for queued events
        max_queue_size: 1000            # max queued events (configured in Storage)
  """

  use GenServer

  require Logger

  alias TowerDB.CircuitBreaker.Storage

  @default_failure_threshold 3
  @default_recovery_timeout 5_000
  @default_queue_retry_interval 100
  @default_queue_retry_attempts 3
  @default_queue_retry_delay 1_000

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
    {:ok, %{state: :closed, failure_count: 0, recovery_timer_ref: nil}}
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
    send(self(), :test_recovery)
    {:noreply, %{state | state: :half_open, recovery_timer_ref: nil}}
  end

  @impl true
  def handle_info(:try_recovery, state), do: {:noreply, state}

  @impl true
  def handle_info(:test_recovery, %{state: :half_open} = state) do
    case Storage.dequeue() do
      :empty ->
        Logger.info("[CircuitBreaker] No queued events, closing circuit")
        {:noreply, close_circuit(state)}

      {:ok, attrs} ->
        case execute_with_retry(fn -> TowerDB.Events.create_event(attrs) end) do
          {:ok, _event} ->
            Logger.info("[CircuitBreaker] Recovery successful, closing circuit")
            schedule_queue_processing()
            {:noreply, close_circuit(state)}

          {:error, reason} ->
            Logger.warning("[CircuitBreaker] Recovery test failed: #{inspect(reason)}")
            Storage.enqueue(attrs)
            {:noreply, open_circuit(state)}
        end
    end
  end

  @impl true
  def handle_info(:test_recovery, state), do: {:noreply, state}

  @impl true
  def handle_info(:process_queue, %{state: :closed} = state) do
    process_queued_events()
    {:noreply, state}
  end

  @impl true
  def handle_info(:process_queue, state), do: {:noreply, state}

  # Private Functions

  defp execute(fun) do
    try do
      case fun.() do
        {:ok, _} = success -> success
        {:error, _} = error -> error
        other ->
          Logger.warning("[CircuitBreaker] Unexpected return value: #{inspect(other)}")
          {:ok, other}
      end
    rescue
      e -> {:error, e}
    catch
      :exit, reason -> {:error, {:exit, reason}}
    end
  end

  defp execute_with_retry(fun) do
    max = config(:queue_retry_attempts, @default_queue_retry_attempts)
    delay = config(:queue_retry_delay, @default_queue_retry_delay)
    do_execute_with_retry(fun, max, delay, 1)
  end

  defp do_execute_with_retry(fun, max, delay, attempt) do
    case execute(fun) do
      {:ok, _} = success ->
        success

      {:error, reason} when attempt < max ->
        Logger.warning("[CircuitBreaker] Attempt #{attempt}/#{max} failed, retrying in #{delay}ms")
        Process.sleep(delay)
        do_execute_with_retry(fun, max, delay, attempt + 1)

      {:error, _} = error ->
        Logger.error("[CircuitBreaker] Failed after #{max} attempts")
        error
    end
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
    if db_error?(attrs) do
      Logger.debug("[CircuitBreaker] Filtering database error - not queuing")
      :ok
    else
      Storage.enqueue(attrs)
    end
  end

  defp db_error?(attrs) do
    reason_str = attrs |> Map.get(:reason) |> inspect() |> String.downcase()

    Enum.any?(~w(dbconnection postgrex econnrefused ecto.adapters.sql), fn pattern ->
      String.contains?(reason_str, pattern)
    end)
  end

  defp schedule_queue_processing do
    interval = config(:queue_retry_interval, @default_queue_retry_interval)
    Process.send_after(self(), :process_queue, interval)
  end

  defp process_queued_events do
    case Storage.dequeue() do
      :empty ->
        Logger.debug("[CircuitBreaker] Queue empty")

      {:ok, attrs} ->
        case execute_with_retry(fn -> TowerDB.Events.create_event(attrs) end) do
          {:ok, event} ->
            Logger.info("[CircuitBreaker] Queued event #{event.id} inserted")
            schedule_queue_processing()

          {:error, _reason} ->
            Storage.enqueue(attrs)
            schedule_recovery_retry()
        end
    end
  end

  defp schedule_recovery_retry do
    timeout = config(:recovery_timeout, @default_recovery_timeout)
    Process.send_after(self(), :process_queue, timeout)
  end

  defp config(key, default) do
    Application.get_env(:tower_db, :circuit_breaker, [])
    |> Keyword.get(key, default)
  end
end
