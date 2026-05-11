defmodule TowerDB.BufferTest do
  use TowerDB.DataCase, async: false

  alias TowerDB.Buffer

  @batch_size 5
  @max_queue_size 10
  @flush_timeout 1_000

  setup do
    buffer = start_supervised!({Buffer,
      name: nil,
      batch_size: @batch_size,
      max_queue_size: @max_queue_size,
      flush_timeout: @flush_timeout
    })

    {:ok, buffer: buffer}
  end

  describe "basic flow" do
    test "flushes when batch size is reached", %{buffer: buffer} do
      for i <- 1..@batch_size do
        Buffer.enqueue(buffer, %{
          datetime: DateTime.utc_now(),
          level: :error,
          reason: %RuntimeError{message: "Error #{i}"}
        })
      end

      Process.sleep(100)

      assert length(TowerDB.Events.list_events()) == @batch_size
    end

    test "does not flush before batch size is reached", %{buffer: buffer} do
      events_count = @batch_size - 2

      for i <- 1..events_count do
        Buffer.enqueue(buffer, %{
          datetime: DateTime.utc_now(),
          level: :error,
          reason: %RuntimeError{message: "Error #{i}"}
        })
      end

      Process.sleep(50)
      assert length(TowerDB.Events.list_events()) == 0

      Process.sleep(@flush_timeout)
      assert length(TowerDB.Events.list_events()) == events_count
    end

    test "flushes multiple batches when queue exceeds batch size", %{buffer: buffer} do
      total_events = @batch_size * 2 + 2

      for i <- 1..total_events do
        Buffer.enqueue(buffer, %{
          datetime: DateTime.utc_now(),
          level: :error,
          reason: %RuntimeError{message: "Error #{i}"}
        })
      end

      Process.sleep(200)
      assert length(TowerDB.Events.list_events()) == @batch_size * 2

      Process.sleep(@flush_timeout + 100)
      assert length(TowerDB.Events.list_events()) == total_events
    end
  end

  describe "queue overflow" do
    import ExUnit.CaptureLog

    test "drops new events when queue reaches max capacity" do
      # Need large batch_size so no flush happens before overflow
      buffer = start_supervised!(
        {Buffer, name: nil, max_queue_size: 10, batch_size: 100},
        id: :overflow_buffer
      )

      log =
        capture_log(fn ->
          for i <- 1..15 do
            Buffer.enqueue(buffer, %{
              datetime: DateTime.utc_now(),
              level: :error,
              reason: %RuntimeError{message: "Error #{i}"}
            })
          end

          Process.sleep(50)
        end)

      assert log =~ "Buffer full, dropping new event"
    end
  end
end
