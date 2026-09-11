defmodule TowerDB.ReporterTest do
  use TowerDB.DataCase, async: false

  import ExUnit.CaptureLog, only: [capture_log: 2]

  alias TowerDB.Reporter

  describe "report_event/1" do
    test "reports error level events" do
      event = build_tower_event(:error, "Error event")

      Reporter.report_event(event)

      events = TowerDB.Events.list_events()
      assert length(events) == 1
      assert hd(events).normalized_reason =~ "Error event"
    end

    test "reports critical level events" do
      event = build_tower_event(:critical, "Critical event")

      Reporter.report_event(event)

      events = TowerDB.Events.list_events()
      assert length(events) == 1
      assert hd(events).normalized_reason =~ "Critical event"
    end

    test "report warning level events" do
      event = build_tower_event(:warning, "Warning event")

      Reporter.report_event(event)

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
      assert db_event.normalized_reason =~ "Test error"
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

  describe "report_event/1 when disabled" do
    test "does not persist the event, logs it, and returns :ok" do
      put_env(:tower_db, :enabled, false)

      original_level = Logger.level()
      Logger.configure(level: :debug)
      on_exit(fn -> Logger.configure(level: original_level) end)

      event = build_tower_event(:error, "Disabled event")

      assert capture_log([level: :debug], fn ->
               assert Reporter.report_event(event) == :ok
             end) =~ "[TowerDB] Reporter disabled, ignoring event"

      assert TowerDB.Events.list_events() == []
    end
  end

  describe "report_event/1 with an invalid :enabled config" do
    test "raises an ArgumentError" do
      put_env(:tower_db, :enabled, "false")

      event = build_tower_event(:error, "Invalid config event")

      assert_raise ArgumentError,
                   "expected :tower_db, :enabled to be a boolean, got: \"false\"",
                   fn -> Reporter.report_event(event) end
    end
  end

  defp put_env(app, key, value) do
    original_value = Application.get_env(app, key)
    Application.put_env(app, key, value)

    on_exit(fn ->
      if original_value == nil do
        Application.delete_env(app, key)
      else
        Application.put_env(app, key, original_value)
      end
    end)
  end

  defp build_tower_event(level, message, opts \\ []) do
    %Tower.Event{
      id: UUIDv7.generate(),
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
