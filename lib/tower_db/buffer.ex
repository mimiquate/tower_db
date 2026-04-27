defmodule TowerDB.Buffer do
  @moduledoc """
  GenServer that buffers events and flushes them in batches.
  """

  use GenServer

  require Logger

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def enqueue(attrs) when is_map(attrs) do
    GenServer.cast(__MODULE__, {:enqueue, attrs})
  end

  @impl true
  def init(_opts) do
    state = %{
      queue: :queue.new(),
      queue_size: 0,
      timer_ref: nil,
      batch_id: 0,
      config: %{
        batch_size: 50,
        flush_timeout: 10_000,
        max_queue_size: 1_000
      }
    }

    {:ok, state}
  end

  @impl true
  def handle_cast({:enqueue, attrs}, state) do

    #drop new events if the buffer has reached its maximum capacity
    if state.queue_size >= state.config.max_queue_size do
      Logger.warning("[TowerDB] Buffer full, dropping new event")
      {:noreply, state}
    else
      new_queue = :queue.in(attrs, state.queue)
      new_size = state.queue_size + 1

      # Start timer when first event arrives
      timer_ref =
        if state.queue_size == 0 do
          Process.send_after(self(), {:flush, state.batch_id}, state.config.flush_timeout)
        else
          state.timer_ref
        end

      new_state = %{state | queue: new_queue, queue_size: new_size, timer_ref: timer_ref}

      if new_size >= state.config.batch_size do
        {:noreply, do_flush(new_state)}
      else
        {:noreply, new_state}
      end
    end
  end

  @impl true
  def handle_info({:flush, batch_id}, state) do
    if batch_id == state.batch_id and state.queue_size > 0 do
      {:noreply, do_flush(state)}
    else
      {:noreply, state}
    end
  end

  defp do_flush(%{queue_size: 0} = state), do: state

  defp do_flush(state) do
    # Cancel timer if exists
    if state.timer_ref, do: Process.cancel_timer(state.timer_ref)

    %{config: config, queue_size: queue_size} = state

    to_take =
      if queue_size >= config.batch_size, do: config.batch_size, else: queue_size

    {batch, remaining_queue} = take_from_queue(state.queue, to_take)
    remaining_size = queue_size - to_take

    Task.Supervisor.start_child(TowerDB.TaskSupervisor, fn ->
      try do
        case TowerDB.BatchInsert.insert_all(batch) do
          {:ok, count} -> Logger.debug("[TowerDB] Inserted #{count} events")
          {:error, reason} -> Logger.error("[TowerDB] Insert failed: #{inspect(reason)}")
        end
      rescue
        e -> Logger.error("[TowerDB] Insert crashed: #{Exception.message(e)}")
      end
    end)

    new_batch_id = state.batch_id + 1

    # Start new timer if there are remaining events
    new_timer_ref =
      if remaining_size > 0 do
        Process.send_after(self(), {:flush, new_batch_id}, state.config.flush_timeout)
      else
        nil
      end

    %{state |
      queue: remaining_queue,
      queue_size: remaining_size,
      timer_ref: new_timer_ref,
      batch_id: new_batch_id
    }
  end

  defp take_from_queue(queue, n) do
    take_from_queue(queue, n, [])
  end

  defp take_from_queue(queue, 0, acc) do
    {Enum.reverse(acc), queue}
  end

  defp take_from_queue(queue, n, acc) do
    if :queue.is_empty(queue) do
      {Enum.reverse(acc), queue}
    else
      {{:value, item}, rest} = :queue.out(queue)
      take_from_queue(rest, n - 1, [item | acc])
    end
  end
end
