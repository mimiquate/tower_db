defmodule TowerDB.BatchInsertTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog
  import TowerDB.TestHelpers

  alias TowerDB.BatchInsert

  setup do
    Ecto.Adapters.SQL.Sandbox.mode(TowerDB.TestRepo, :auto)
    run_migration(:down)
    run_migration(:up)
    :ok
  end

  describe "insert_all/1" do
    test "inserts multiple events" do
      attrs =
        for i <- 1..10 do
          %{
            datetime: DateTime.utc_now(),
            level: :error,
            reason: %RuntimeError{message: "Event #{i}"}
          }
        end

      assert {:ok, 10} = BatchInsert.insert_all(attrs)

      events = TowerDB.Events.list_events()
      assert length(events) == 10
    end

    test "inserts events with all fields" do
      stacktrace = [{__MODULE__, :test, 0, [file: ~c"test.ex", line: 1]}]
      metadata = %{request_id: "abc123", user_id: 42}

      attrs = [
        %{
          datetime: ~U[2026-05-08 12:00:00.000000Z],
          level: :critical,
          reason: %ArgumentError{message: "Full event"},
          stacktrace: stacktrace,
          metadata: metadata
        }
      ]

      assert {:ok, 1} = BatchInsert.insert_all(attrs)

      [event] = TowerDB.Events.list_events()
      assert event.datetime == ~U[2026-05-08 12:00:00.000000Z]
      assert event.level == :critical
      assert event.reason == %ArgumentError{message: "Full event"}
      assert event.stacktrace == stacktrace
      assert event.metadata == metadata
    end

    test "returns error for invalid event (missing required fields)" do
      attrs = [
        %{
          datetime: DateTime.utc_now(),
          level: :error
          # missing reason
        }
      ]

      log =
        capture_log(fn ->
          assert {:error, changeset} = BatchInsert.insert_all(attrs)
          assert changeset.errors[:reason] != nil
        end)

      assert log =~ "[TowerDB] Batch insert error"
    end

    test "transaction rolls back all events if one fails" do
      attrs = [
        %{
          datetime: DateTime.utc_now(),
          level: :error,
          reason: "valid event"
        },
        %{
          datetime: DateTime.utc_now(),
          level: :error
          # missing reason - will fail
        }
      ]

      capture_log(fn ->
        assert {:error, _} = BatchInsert.insert_all(attrs)
      end)

      events = TowerDB.Events.list_events()
      assert length(events) == 0
    end

    test "handles large batch of events" do
      attrs =
        for i <- 1..100 do
          %{
            datetime: DateTime.utc_now(),
            level: :error,
            reason: %RuntimeError{message: "Large batch event #{i}"},
            stacktrace: [{__MODULE__, :test, i, [file: ~c"test.ex", line: i]}],
            metadata: %{index: i}
          }
        end

      assert {:ok, 100} = BatchInsert.insert_all(attrs)

      events = TowerDB.Events.list_events()
      assert length(events) == 100
    end

    test "handles events with complex reason types" do
      attrs = [
        %{
          datetime: DateTime.utc_now(),
          level: :error,
          reason: {:exit, :normal}
        },
        %{
          datetime: DateTime.utc_now(),
          level: :error,
          reason: %KeyError{key: :missing, term: %{}}
        }
      ]

      assert {:ok, 2} = BatchInsert.insert_all(attrs)

      events = TowerDB.Events.list_events()
      reasons = Enum.map(events, & &1.reason)

      assert {:exit, :normal} in reasons
      assert %KeyError{key: :missing, term: %{}} in reasons
    end
  end
end
