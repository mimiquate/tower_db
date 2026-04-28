defmodule TowerDB.BufferTest do
  use ExUnit.Case

  alias TowerDB.Buffer

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(TowerDB.TestRepo)
    Ecto.Adapters.SQL.Sandbox.mode(TowerDB.TestRepo, {:shared, self()})

    # Stop the application-started Buffer to start a fresh one for each test
    if Process.whereis(Buffer) do
      GenServer.stop(Buffer)
    end

    {:ok, _pid} = Buffer.start_link()

    :ok
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
        TowerDB.TestRepo.aggregate(TowerDB.Schema.Event, :count)

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
        TowerDB.TestRepo.aggregate(TowerDB.Schema.Event, :count)

      assert count == 0
    end

    test "flushes multiple batches when queue exceeds batch size" do
      batch_size = 50
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
        TowerDB.TestRepo.aggregate(TowerDB.Schema.Event, :count)

      assert count == 100
    end
  end
end
