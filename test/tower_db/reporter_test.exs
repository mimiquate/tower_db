defmodule TowerDB.ReporterTest do
  use TowerDB.DataCase, async: false

  alias TowerDB.Reporter

  describe "report_event/1" do
    test "reports error level events" do
      event = build_tower_event(:error, "Error event")

      assert :ok = Reporter.report_event(event)

      events = TowerDB.Events.list_events()
      assert length(events) == 1
      assert match?(%RuntimeError{message: "Error event"}, hd(events).reason)
    end

    test "reports critical level events" do
      event = build_tower_event(:critical, "Critical event")

      assert :ok = Reporter.report_event(event)

      events = TowerDB.Events.list_events()
      assert length(events) == 1
      assert match?(%RuntimeError{message: "Critical event"}, hd(events).reason)
    end

    test "report warning level events" do
      event = build_tower_event(:warning, "Warning event")

      assert :ok = Reporter.report_event(event)

      events = TowerDB.Events.list_events()
      assert length(events) == 1
    end

    test "extracts all event attributes correctly" do
      stacktrace = [{__MODULE__, :test, 0, [file: ~c"test.ex", line: 1]}]
      metadata = %{request_id: "abc123", user_id: 42}

      event =
        build_tower_event(:error, "Test error",
          datetime: ~U[2026-05-08 12:00:00.000000Z],
          stacktrace: stacktrace,
          metadata: metadata
        )

      Reporter.report_event(event)

      [db_event] = TowerDB.Events.list_events()

      assert db_event.datetime == ~U[2026-05-08 12:00:00.000000Z]
      assert db_event.level == :error
      assert db_event.reason == %RuntimeError{message: "Test error"}
      assert db_event.stacktrace == stacktrace
      assert db_event.metadata == metadata
    end

    test "handles events with nil optional fields" do
      event =
        build_tower_event(:error, "Nil fields",
          stacktrace: nil,
          metadata: nil
        )

      Reporter.report_event(event)

      [db_event] = TowerDB.Events.list_events()

      assert db_event.stacktrace == nil
      assert db_event.metadata == nil
    end
  end

  defp build_tower_event(level, message, opts \\ []) do
    %Tower.Event{
      id: "test-#{System.unique_integer()}",
      similarity_id: :rand.uniform(100_000),
      datetime: Keyword.get(opts, :datetime, DateTime.utc_now()),
      level: level,
      kind: :error,
      reason: %RuntimeError{message: message},
      stacktrace:
        Keyword.get(opts, :stacktrace, [{__MODULE__, :test, 0, [file: ~c"test.ex", line: 1]}]),
      metadata: Keyword.get(opts, :metadata, %{}),
      log_event: nil,
      plug_conn: nil,
      by: nil
    }
  end
end
