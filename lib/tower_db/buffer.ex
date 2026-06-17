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
    new_buffer = [attrs | state.buffer]
    new_state = %{state | buffer: new_buffer, total_received: state.total_received + 1}

    batch_size = config(:batch_size, @default_batch_size)

    if length(new_buffer) >= batch_size do
      {:noreply, do_flush(new_state)}
    else
      {:noreply, ensure_timer(new_state)}
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

  # Private Functions

  defp do_flush(%{buffer: []} = state) do
    cancel_timer(state.flush_timer_ref)
    %{state | flush_timer_ref: nil}
  end

  defp do_flush(state) do
    cancel_timer(state.flush_timer_ref)
    events = Enum.reverse(state.buffer)
    event_count = length(events)

    Logger.info("[Buffer] Flushing batch (#{event_count} events)")

    # Flush asynchronously to avoid blocking the buffer process
    Task.start(fn ->
      CircuitBreaker.call_batch(events, fn ->
        TowerDB.Events.create_events_batch(events)
      end)
    end)

    %{state |
      buffer: [],
      flush_timer_ref: nil,
      total_flushed: state.total_flushed + event_count
    }
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
