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
    enqueue(__MODULE__, attrs)
  end

  def enqueue(server, attrs) when is_map(attrs) do
    GenServer.cast(server, {:enqueue, attrs})
  end

  @impl true
  def init(opts) do
    config =
      @default_config
      |> Map.merge(Map.new(Keyword.take(opts, [:batch_size, :flush_timeout, :max_queue_size])))

    state = %{
      queue: :queue.new(),
      queue_size: 0,
      pending_batches: %{},
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

  def handle_info({:batch_result, batch_id, :ok, count}, state) do
    Logger.debug("[TowerDB] Inserted #{count} events")
    {:noreply, %{state | pending_batches: Map.delete(state.pending_batches, batch_id)}}
  end

  def handle_info({:batch_result, batch_id, :error, reason}, state) do
    Logger.error("[TowerDB] Insert failed: #{inspect(reason)}")

    case Map.pop(state.pending_batches, batch_id) do
      {nil, _} ->
        {:noreply, state}

      {events, pending_batches} ->
        new_queue = Enum.reduce(Enum.reverse(events), state.queue, &:queue.in_r/2)
        new_size = state.queue_size + length(events)

        new_state = %{state |
          queue: new_queue,
          queue_size: new_size,
          pending_batches: pending_batches
        }

        {:noreply, schedule_retry_flush(new_state)}
    end
  end

  defp do_flush(%{queue_size: 0} = state), do: state

  defp do_flush(state) do
    %{config: config, queue_size: queue_size} = state

    to_take =
      if queue_size >= config.batch_size, do: config.batch_size, else: queue_size

    {batch, remaining_queue} = take_from_queue(state.queue, to_take)
    buffer_pid = self()
    batch_id = state.batch_id

    task_result = Task.Supervisor.start_child(TowerDB.TaskSupervisor, fn ->
      result =
        try do
          TowerDB.BatchInsert.insert_all(batch)
        rescue
          e -> {:error, e}
        end

      case result do
        {:ok, count} -> send(buffer_pid, {:batch_result, batch_id, :ok, count})
        {:error, reason} -> send(buffer_pid, {:batch_result, batch_id, :error, reason})
      end
    end)

    case task_result do
      {:ok, _pid} ->
        if state.timer_ref, do: Process.cancel_timer(state.timer_ref)

        remaining_size = queue_size - to_take
        new_batch_id = state.batch_id + 1

        new_timer_ref =
          if remaining_size > 0 do
            Process.send_after(self(), {:flush, new_batch_id}, config.flush_timeout)
          else
            nil
          end

        %{state |
          queue: remaining_queue,
          queue_size: remaining_size,
          pending_batches: Map.put(state.pending_batches, batch_id, batch),
          timer_ref: new_timer_ref,
          batch_id: new_batch_id
        }

      {:error, :max_children} ->
        Logger.warning("[TowerDB] Max concurrent tasks reached, will retry later")
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
