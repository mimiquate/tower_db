defmodule TowerDB.ReporterTest do
  use TowerDB.DataCase, async: false

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

    test "attaches request_data when plug_conn is present" do
      conn =
        Plug.Test.conn(:get, "/users/1")
        |> Map.put(:host, "example.com")
        |> Map.put(:port, 80)
        |> Map.put(:scheme, :http)
        |> Map.put(:remote_ip, {127, 0, 0, 1})
        |> Plug.Conn.put_req_header("user-agent", "ExampleBrowser/1.0")

      event = build_tower_event(:error, "With conn", plug_conn: conn)

      Reporter.report_event(event)

      [db_event] = TowerDB.Events.list_events()

      assert db_event.request_data["url"] == "http://example.com:80/users/1"
      assert db_event.request_data["method"] == "GET"
      assert db_event.request_data["headers"] == %{"user-agent" => "ExampleBrowser/1.0"}
    end

    test "leaves request_data nil when plug_conn is absent" do
      event = build_tower_event(:error, "No conn")

      Reporter.report_event(event)

      [db_event] = TowerDB.Events.list_events()

      assert db_event.request_data == nil
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
      plug_conn: Keyword.get(opts, :plug_conn),
      by: nil
    }
  end
end
