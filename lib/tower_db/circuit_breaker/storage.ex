defmodule TowerDB.CircuitBreaker.Storage do
  @moduledoc """
  ETS-based storage for queued events when the circuit breaker is open.

  This GenServer owns the ETS table, ensuring the queue survives
  CircuitBreaker process restarts.
  """

  use GenServer

  @table :tower_db_circuit_breaker_queue
  @default_max_size 1000

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Enqueue an event attrs map for later retry.
  Returns :ok if enqueued, :dropped if queue is full.
  """
  def enqueue(attrs) do
    GenServer.call(__MODULE__, {:enqueue, attrs})
  end

  @doc """
  Dequeue the oldest event from the queue.
  Returns {:ok, attrs} or :empty.
  """
  def dequeue do
    GenServer.call(__MODULE__, :dequeue)
  end

  @doc """
  Re-queue an event at the front of the queue (preserves ordering on retry).
  Unlike enqueue, this does not check max_size since the event was already in the queue.
  """
  def requeue(attrs) do
    GenServer.call(__MODULE__, {:requeue, attrs})
  end

  @doc """
  Returns the current queue size.
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
  Returns stats about the queue: size, dropped count, enqueued and dropped count.
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
  def handle_call({:enqueue, attrs}, _from, state) do
    max = max_size()
    current_size = :ets.info(state.table, :size)

    if current_size >= max do
      {:reply, :dropped, %{state | dropped: state.dropped + 1}}
    else
      counter = state.counter + 1
      :ets.insert(state.table, {counter, attrs})
      {:reply, :ok, %{state | counter: counter, enqueued: state.enqueued + 1}}
    end
  end

  @impl true
  def handle_call(:dequeue, _from, state) do
    case :ets.first(state.table) do
      :"$end_of_table" ->
        {:reply, :empty, state}

      key ->
        [{^key, attrs}] = :ets.lookup(state.table, key)
        :ets.delete(state.table, key)
        {:reply, {:ok, attrs}, %{state | dequeued: state.dequeued + 1}}
    end
  end

  @impl true
  def handle_call({:requeue, attrs}, _from, state) do
    case :ets.first(state.table) do
      :"$end_of_table" ->
        # Queue is empty, just insert with current counter
        counter = state.counter + 1
        :ets.insert(state.table, {counter, attrs})
        {:reply, :ok, %{state | counter: counter, enqueued: state.enqueued + 1}}

      min_key ->
        # Insert before the minimum key to preserve order
        :ets.insert(state.table, {min_key - 1, attrs})
        {:reply, :ok, %{state | enqueued: state.enqueued + 1}}
    end
  end

  @impl true
  def handle_call(:stats, _from, state) do
    stats = %{
      queue_size: :ets.info(state.table, :size),
      max_size: max_size(),
      total_enqueued: state.enqueued,
      total_dequeued: state.dequeued,
      total_dropped: state.dropped
    }

    {:reply, stats, state}
  end

  defp config do
    Application.get_env(:tower_db, :circuit_breaker, [])
  end
end
