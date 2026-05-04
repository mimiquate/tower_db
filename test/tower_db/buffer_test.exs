defmodule TowerDB.BufferTest do
  use ExUnit.Case, async: false

  alias TowerDB.Buffer

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(TowerDB.TestRepo)
    Ecto.Adapters.SQL.Sandbox.mode(TowerDB.TestRepo, {:shared, self()})

    # Ensure TaskSupervisor is running
    task_sup =
      case Process.whereis(TowerDB.TaskSupervisor) do
        nil ->
          {:ok, pid} = Task.Supervisor.start_link(name: TowerDB.TaskSupervisor, max_children: 5)
          pid

        pid ->
          pid
      end

    # Ensure Buffer is running
    buffer =
      case Process.whereis(Buffer) do
        nil ->
          {:ok, pid} = Buffer.start_link()
          pid

        pid ->
          pid
      end

    {:ok, buffer: buffer, task_sup: task_sup}
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
end
