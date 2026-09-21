defmodule TowerDB.BurstProtector do
  @moduledoc """
  Simple, global burst protection for `TowerDB.Reporter`.

  Counts every event added within the current fixed time window. While
  `count` is under `max_count`, `add/1` creates the event and increments the
  count. Once `max_count` is reached, further events are dropped until the
  window resets to `0`.
  """

  use GenServer

  alias TowerDB.Events
  alias __MODULE__, as: State

  defstruct max_count: 100,
            interval: 10,
            count: 0

  @doc """
  Creates the event through `TowerDB.Events.create_event/1` and counts it
  against the current window, unless `max_count` has already been reached
  for that window, in which case the event is dropped.
  """
  def add(attrs) do
    GenServer.call(__MODULE__, {:add, attrs})
  end

  def start_link(opts \\ []) do
    state = struct!(State, opts)
    state = %{state | interval: state.interval * 1_000}

    GenServer.start_link(__MODULE__, state, name: __MODULE__)
  end

  @impl true
  def init(state) do
    {:ok, schedule_reset(state)}
  end

  @impl true
  def handle_call({:add, attrs}, _from, %State{count: count, max_count: max_count} = state)
      when count < max_count do
    {:reply, Events.create_event(attrs), %{state | count: count + 1}}
  end

  def handle_call({:add, _attrs}, _from, state) do
    {:reply, :dropped, state}
  end

  @impl true
  def handle_info(:reset, state) do
    {:noreply, schedule_reset(%{state | count: 0})}
  end

  def handle_info(_message, state) do
    {:noreply, state}
  end

  defp schedule_reset(state) do
    Process.send_after(self(), :reset, state.interval)
    state
  end
end
