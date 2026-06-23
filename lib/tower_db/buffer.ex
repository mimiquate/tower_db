defmodule TowerDB.Buffer do
  @moduledoc """
  Buffer that accumulates events and flushes them in batches to the circuit breaker.

  Events are flushed when either:
  - The buffer reaches `batch_size` (default: 50 events)
  - The `flush_interval` timer fires (default: 500ms)

  ## Configuration

      config :tower_db, :buffer,
        batch_size: 50,        # max events per batch
        flush_interval: 500    # ms before forced flush
  """

  use GenServer

  require Logger

  alias TowerDB.CircuitBreaker

  @default_batch_size 50
  @default_flush_interval 500
  @default_backpressure_retry 1000

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Add an event to the buffer. Non-blocking (cast).
  The event will be flushed to the database in a batch.
  """
  def add(attrs) when is_map(attrs) do
    GenServer.cast(__MODULE__, {:add, attrs})
  end

  @doc """
  Force an immediate flush of buffered events.
  Useful for testing or graceful shutdown.
  """
  def flush do
    GenServer.call(__MODULE__, :flush)
  end

  @doc """
  Get buffer statistics.
  """
  def state do
    GenServer.call(__MODULE__, :state)
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    {:ok, %{
      buffer: [],
      flush_timer_ref: nil,
      total_received: 0,
      total_flushed: 0
    }}
  end

  @impl true
  def handle_cast({:add, attrs}, state) do
    if skip_event?(attrs) do
      {:noreply, state}
    else
      new_buffer = [attrs | state.buffer]
      new_state = %{state | buffer: new_buffer, total_received: state.total_received + 1}

      batch_size = config(:batch_size, @default_batch_size)

      if length(new_buffer) >= batch_size do
        {:noreply, do_flush(new_state)}
      else
        {:noreply, ensure_timer(new_state)}
      end
    end
  end

  @impl true
  def handle_call(:flush, _from, state) do
    new_state = do_flush(state)
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:state, _from, state) do
    stats = %{
      buffer_size: length(state.buffer),
      total_received: state.total_received,
      total_flushed: state.total_flushed
    }

    {:reply, stats, state}
  end

  @impl true
  def handle_info(:flush, state) do
    {:noreply, do_flush(%{state | flush_timer_ref: nil})}
  end

  @impl true
  def handle_info(:retry_flush, state) do
    {:noreply, do_flush(%{state | flush_timer_ref: nil})}
  end

  # Private Functions

  defp do_flush(%{buffer: []} = state) do
    cancel_timer(state.flush_timer_ref)
    %{state | flush_timer_ref: nil}
  end

  defp do_flush(state) do
    cancel_timer(state.flush_timer_ref)

    if CircuitBreaker.can_accept?() do
      flush_to_circuit_breaker(state)
    else
      Logger.info("[Buffer] CircuitBreaker not ready, holding #{length(state.buffer)} events")
      schedule_retry(state)
    end
  end

  defp flush_to_circuit_breaker(state) do
    events =
      state.buffer
      |> Enum.reverse()
      |> Enum.reject(&skip_event?/1)

    if Enum.empty?(events) do
      %{state | buffer: [], flush_timer_ref: nil}
    else
      event_count = length(events)
      Logger.info("[Buffer] Flushing batch (#{event_count} events)")

      CircuitBreaker.call_batch(events, fn ->
        TowerDB.Events.create_events_batch(events)
      end)

      %{state |
        buffer: [],
        flush_timer_ref: nil,
        total_flushed: state.total_flushed + event_count
      }
    end
  end

  # Filter DB-related errors that shouldn't be stored
  defp skip_event?(%{reason: %Tower.ReportEventError{}}), do: true
  defp skip_event?(%{reason: %DBConnection.ConnectionError{}}), do: true
  defp skip_event?(%{reason: %Postgrex.Error{}}), do: true
  defp skip_event?(%{reason: reason}) when reason != nil do
    reason
    |> inspect()
    |> String.downcase()
    |> db_error_string?()
  end
  defp skip_event?(_), do: false

  defp db_error_string?(reason_str) do
    db_patterns = [
      "dbconnection",
      "postgrex",
      "econnrefused",
      "connection_refused",
      "ecto.adapters",
      "tcp connect",
      "connection not available",
      "dropped from queue"
    ]

    Enum.any?(db_patterns, &String.contains?(reason_str, &1))
  end

  defp schedule_retry(state) do
    retry_interval = config(:backpressure_retry, @default_backpressure_retry)
    ref = Process.send_after(self(), :retry_flush, retry_interval)
    %{state | flush_timer_ref: ref}
  end

  defp ensure_timer(%{flush_timer_ref: nil} = state) do
    interval = config(:flush_interval, @default_flush_interval)
    ref = Process.send_after(self(), :flush, interval)
    %{state | flush_timer_ref: ref}
  end

  defp ensure_timer(state), do: state

  defp cancel_timer(nil), do: :ok
  defp cancel_timer(ref), do: Process.cancel_timer(ref)

  defp config(key, default) do
    Application.get_env(:tower_db, :buffer, [])
    |> Keyword.get(key, default)
  end
end
