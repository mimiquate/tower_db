defmodule TowerDB.CircuitBreaker.Storage do
  @moduledoc """
  ETS-based storage for queued event batches when the circuit breaker is open.

  This GenServer owns the ETS table, ensuring the queue survives
  CircuitBreaker process restarts.
  """

  use GenServer

  @table :tower_db_circuit_breaker_queue
  @default_max_size 20

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Enqueue a batch of event attrs for later retry.
  Returns :ok if enqueued, :dropped if queue is full.
  """
  def enqueue(attrs_list) when is_list(attrs_list) do
    GenServer.call(__MODULE__, {:enqueue, attrs_list})
  end

  @doc """
  Dequeue the oldest batch from the queue.
  Returns {:ok, attrs_list} or :empty.
  """
  def dequeue do
    GenServer.call(__MODULE__, :dequeue)
  end

  @doc """
  Re-queue a batch at the front of the queue (preserves ordering on retry).
  Unlike enqueue, this does not check max_size since the batch was already in the queue.
  """
  def requeue(attrs_list) when is_list(attrs_list) do
    GenServer.call(__MODULE__, {:requeue, attrs_list})
  end

  @doc """
  Returns the current queue size (number of batches).
  """
  def queue_size do
    case :ets.info(@table) do
      :undefined -> 0
      info -> Keyword.get(info, :size, 0)
    end
  end

  @doc """
  Get the configured max queue size.
  """
  def max_size do
    config()[:max_queue_size] || @default_max_size
  end

  @doc """
  Returns stats about the queue: batch count, and event counts (enqueued, dequeued, dropped).
  """
  def state do
    GenServer.call(__MODULE__, :stats)
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    table = :ets.new(@table, [:ordered_set, :named_table, :public, read_concurrency: true])
    {:ok, %{table: table, counter: 0, dropped: 0, enqueued: 0, dequeued: 0}}
  end

  @impl true
  def handle_call({:enqueue, attrs_list}, _from, state) do
    max = max_size()
    current_size = :ets.info(state.table, :size)
    event_count = length(attrs_list)

    if current_size >= max do
      {:reply, :dropped, %{state | dropped: state.dropped + event_count}}
    else
      counter = state.counter + 1
      :ets.insert(state.table, {counter, attrs_list})
      {:reply, :ok, %{state | counter: counter, enqueued: state.enqueued + event_count}}
    end
  end

  @impl true
  def handle_call(:dequeue, _from, state) do
    case :ets.first(state.table) do
      :"$end_of_table" ->
        {:reply, :empty, state}

      key ->
        [{^key, attrs_list}] = :ets.lookup(state.table, key)
        :ets.delete(state.table, key)
        {:reply, {:ok, attrs_list}, %{state | dequeued: state.dequeued + length(attrs_list)}}
    end
  end

  @impl true
  def handle_call({:requeue, attrs_list}, _from, state) do
    event_count = length(attrs_list)

    case :ets.first(state.table) do
      :"$end_of_table" ->
        # Queue is empty, just insert with current counter
        counter = state.counter + 1
        :ets.insert(state.table, {counter, attrs_list})
        {:reply, :ok, %{state | counter: counter, enqueued: state.enqueued + event_count}}

      min_key ->
        # Insert before the minimum key to preserve order
        :ets.insert(state.table, {min_key - 1, attrs_list})
        {:reply, :ok, %{state | enqueued: state.enqueued + event_count}}
    end
  end

  @impl true
  def handle_call(:stats, _from, state) do
    stats = %{
      batch_count: :ets.info(state.table, :size),
      max_batch_count: max_size(),
      events_enqueued: state.enqueued,
      events_dequeued: state.dequeued,
      events_dropped: state.dropped
    }

    {:reply, stats, state}
  end

  defp config do
    Application.get_env(:tower_db, :circuit_breaker, [])
  end
end
