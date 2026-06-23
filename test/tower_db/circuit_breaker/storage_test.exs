defmodule TowerDB.CircuitBreaker.StorageTest do
  use ExUnit.Case, async: false

  alias TowerDB.CircuitBreaker.Storage

  setup do
    stop_supervisor()
    stop_process(Storage)

    {:ok, _pid} = Storage.start_link()

    on_exit(fn ->
      stop_process(Storage)
    end)

    :ok
  end

  defp stop_supervisor do
    case Process.whereis(TowerDB.Supervisor) do
      nil -> :ok
      pid -> Supervisor.stop(pid)
    end
  end

  defp stop_process(name) do
    case Process.whereis(name) do
      nil -> :ok
      pid ->
        try do
          GenServer.stop(pid, :normal, 100)
        catch
          :exit, _ -> :ok
        end
    end

    Process.sleep(10)
  end

  describe "enqueue/1" do
    test "enqueues multiple events" do
      for i <- 1..5 do
        assert :ok = Storage.enqueue(%{id: i})
      end

      assert Storage.queue_size() == 5
    end

    test "returns :dropped when queue is full" do
      # Set a small max size for testing
      Application.put_env(:tower_db, :circuit_breaker, max_queue_size: 3)

      on_exit(fn ->
        Application.delete_env(:tower_db, :circuit_breaker)
      end)

      # Fill the queue
      assert :ok = Storage.enqueue(%{id: 1})
      assert :ok = Storage.enqueue(%{id: 2})
      assert :ok = Storage.enqueue(%{id: 3})

      # This should be dropped
      assert :dropped = Storage.enqueue(%{id: 4})
      assert Storage.queue_size() == 3
    end
  end

  describe "dequeue/0" do
    test "returns :empty for empty queue" do
      assert :empty = Storage.dequeue()
    end

    test "returns {:ok, attrs} and removes event from queue" do
      attrs = %{reason: "test", level: :error}
      Storage.enqueue(attrs)

      assert {:ok, ^attrs} = Storage.dequeue()
      assert Storage.queue_size() == 0
    end

    test "maintains FIFO order" do
      Storage.enqueue(%{id: 1})
      Storage.enqueue(%{id: 2})
      Storage.enqueue(%{id: 3})

      assert {:ok, %{id: 1}} = Storage.dequeue()
      assert {:ok, %{id: 2}} = Storage.dequeue()
      assert {:ok, %{id: 3}} = Storage.dequeue()
      assert :empty = Storage.dequeue()
    end
  end

  describe "requeue/1" do
    test "inserts event at front of queue" do
      Storage.enqueue(%{id: 1})
      Storage.enqueue(%{id: 2})

      Storage.requeue(%{id: 0})

      assert {:ok, %{id: 0}} = Storage.dequeue()
      assert {:ok, %{id: 1}} = Storage.dequeue()
      assert {:ok, %{id: 2}} = Storage.dequeue()
    end

    test "does not check max_size" do
      Application.put_env(:tower_db, :circuit_breaker, max_queue_size: 2)

      on_exit(fn ->
        Application.delete_env(:tower_db, :circuit_breaker)
      end)

      # Fill the queue
      Storage.enqueue(%{id: 1})
      Storage.enqueue(%{id: 2})

      # Requeue should work even though queue is full
      assert :ok = Storage.requeue(%{id: 0})
      assert Storage.queue_size() == 3
    end
  end

  describe "queue_size/0" do
    test "returns 0 for empty queue" do
      assert Storage.queue_size() == 0
    end

    test "returns correct count after operations" do
      Storage.enqueue(%{id: 1})
      Storage.enqueue(%{id: 2})
      assert Storage.queue_size() == 2

      Storage.dequeue()
      assert Storage.queue_size() == 1
    end
  end

  describe "state/0" do
    test "tracks dequeued count" do
      Storage.enqueue(%{id: 1})
      Storage.enqueue(%{id: 2})

      stats = Storage.state()
      assert stats.total_enqueued == 2

      Storage.dequeue()

      stats = Storage.state()
      assert stats.total_dequeued == 1
    end

    test "tracks dropped count" do
      Application.put_env(:tower_db, :circuit_breaker, max_queue_size: 1)

      on_exit(fn ->
        Application.delete_env(:tower_db, :circuit_breaker)
      end)

      Storage.enqueue(%{id: 1})
      Storage.enqueue(%{id: 2})
      Storage.enqueue(%{id: 3})

      stats = Storage.state()
      assert stats.total_dropped == 2
    end
  end
end
