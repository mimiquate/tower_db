defmodule TowerDB.BufferTest do
  use ExUnit.Case, async: false

  import TowerDB.TestHelpers

  alias TowerDB.Buffer

  setup do
    Ecto.Adapters.SQL.Sandbox.mode(TowerDB.TestRepo, :auto)

    # Ensure TaskSupervisor is running
    task_sup =
      case Process.whereis(TowerDB.TaskSupervisor) do
        nil ->
          {:ok, pid} = Task.Supervisor.start_link(name: TowerDB.TaskSupervisor, max_children: 5)
          pid

        pid ->
          pid
      end

    # Ensure Buffer is running (managed by TowerDB.Application supervisor)
    buffer =
      case Process.whereis(Buffer) do
        nil ->
          {:ok, pid} = Buffer.start_link()
          pid

        pid ->
          pid
      end

    # Wait for any pending tasks from previous tests to complete
    wait_for_tasks_to_complete(task_sup)

    # Now safe to clean up and create fresh table
    run_migration(:down)
    run_migration(:up)

    {:ok, buffer: buffer, task_sup: task_sup}
  end

  defp wait_for_tasks_to_complete(task_sup) do
    case Task.Supervisor.children(task_sup) do
      [] ->
        :ok

      _children ->
        Process.sleep(100)
        wait_for_tasks_to_complete(task_sup)
    end
  end

  describe "basic flow" do
    test "flushes when batch size is reached" do
      batch_size = 50

      for i <- 1..batch_size do
        Buffer.enqueue(%{
          datetime: DateTime.utc_now(),
          level: :error,
          reason: %RuntimeError{message: "Error #{i}"}
        })
      end

      Process.sleep(100)

      count =
        length(TowerDB.Events.list_events)

      assert count == batch_size
    end

    test "does not flush before batch size is reached" do
      for i <- 1..10 do
        Buffer.enqueue(%{
          datetime: DateTime.utc_now(),
          level: :error,
          reason: %RuntimeError{message: "Error #{i}"}
        })
      end

      Process.sleep(50)

      count =
        length(TowerDB.Events.list_events)


      assert count == 0

      Process.sleep(10000)

      count =
        length(TowerDB.Events.list_events)


      assert count == 10
    end

    test "flushes multiple batches when queue exceeds batch size" do
      total_events = 120

      for i <- 1..total_events do
        Buffer.enqueue(%{
          datetime: DateTime.utc_now(),
          level: :error,
          reason: %RuntimeError{message: "Error #{i}"}
        })
      end

      Process.sleep(200)

      count =
        length(TowerDB.Events.list_events)

      assert count == 100

      Process.sleep(10000)

      count =
        length(TowerDB.Events.list_events)

      assert count == 120
    end
  end

  describe "queue overflow" do
    import ExUnit.CaptureLog

    test "drops new events when queue reaches max capacity" do
      # Start an isolated buffer with small max_queue_size and large batch_size
      # Large batch_size ensures no automatic flushes happen
      buffer = start_supervised!({Buffer, name: nil, max_queue_size: 10, batch_size: 100})

      log =
        capture_log(fn ->
          # Enqueue more events than max_queue_size
          for i <- 1..15 do
            GenServer.cast(buffer, {:enqueue, %{
              datetime: DateTime.utc_now(),
              level: :error,
              reason: %RuntimeError{message: "Error #{i}"}
            }})
          end

          # Allow time for async casts to be processed
          Process.sleep(50)
        end)

      assert log =~ "Buffer full, dropping new event"
    end
  end
end
