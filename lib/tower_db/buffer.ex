defmodule TowerDB.Buffer do
  @moduledoc """
  GenServer that buffers events and flushes them in batches.
  """

  use GenServer

  require Logger

  @default_config %{
    batch_size: 50,
    flush_timeout: 10_000,
    max_queue_size: 1_000
  }

  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)
    server_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, server_opts)
  end

  def enqueue(attrs) when is_map(attrs) do
    GenServer.cast(__MODULE__, {:enqueue, attrs})
  end

  @impl true
  def init(opts) do
    config =
      @default_config
      |> Map.merge(Map.new(Keyword.take(opts, [:batch_size, :flush_timeout, :max_queue_size])))

    state = %{
      queue: :queue.new(),
      queue_size: 0,
      timer_ref: nil,
      batch_id: 0,
      config: config
    }

    {:ok, state}
  end

  @impl true
  def handle_cast({:enqueue, attrs}, state) do
    # Drop new events if the buffer has reached its maximum capacity
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
    %{config: config, queue_size: queue_size} = state

    to_take =
      if queue_size >= config.batch_size, do: config.batch_size, else: queue_size

    # Peek at the batch without removing from queue
    batch = peek_from_queue(state.queue, to_take)

    task_result =
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

    case task_result do
      {:ok, _pid} ->
        # Task started successfully, now remove events from queue
        {_batch, remaining_queue} = take_from_queue(state.queue, to_take)

        # Cancel timer if exists
        if state.timer_ref, do: Process.cancel_timer(state.timer_ref)

        remaining_size = queue_size - to_take
        new_batch_id = state.batch_id + 1

        # Start new timer if there are remaining events
        new_timer_ref =
          if remaining_size > 0 do
            Process.send_after(self(), {:flush, new_batch_id}, config.flush_timeout)
          else
            nil
          end

        %{state |
          queue: remaining_queue,
          queue_size: remaining_size,
          timer_ref: new_timer_ref,
          batch_id: new_batch_id
        }

      {:error, :max_children} ->
        # Max concurrent tasks reached, queue unchanged, retry later
        Logger.debug("[TowerDB] Max concurrent flushes reached, will retry later")
        schedule_retry_flush(state)
    end
  end

  defp schedule_retry_flush(state) do
    # Cancel existing timer and schedule a retry
    if state.timer_ref, do: Process.cancel_timer(state.timer_ref)

    new_batch_id = state.batch_id + 1
    # Retry using the configured flush_timeout
    new_timer_ref = Process.send_after(self(), {:flush, new_batch_id}, state.config.flush_timeout)

    %{state | timer_ref: new_timer_ref, batch_id: new_batch_id}
  end

  defp peek_from_queue(queue, n) do
    peek_from_queue(queue, n, [])
  end

  defp peek_from_queue(_queue, 0, acc), do: Enum.reverse(acc)

  defp peek_from_queue(queue, n, acc) do
    case :queue.out(queue) do
      {:empty, _} -> Enum.reverse(acc)
      {{:value, item}, rest} -> peek_from_queue(rest, n - 1, [item | acc])
    end
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
