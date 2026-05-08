defmodule TowerDB.ReporterTest do
  use ExUnit.Case, async: false

  import TowerDB.TestHelpers

  alias TowerDB.Reporter
  alias TowerDB.Buffer

  setup do
    Ecto.Adapters.SQL.Sandbox.mode(TowerDB.TestRepo, :auto)

    task_sup =
      case Process.whereis(TowerDB.TaskSupervisor) do
        nil ->
          {:ok, pid} = Task.Supervisor.start_link(name: TowerDB.TaskSupervisor, max_children: 5)
          pid

        pid ->
          pid
      end

    buffer =
      case Process.whereis(Buffer) do
        nil ->
          {:ok, pid} = Buffer.start_link()
          pid

        pid ->
          pid
      end

    wait_for_tasks_to_complete(task_sup)

    run_migration(:down)
    run_migration(:up)

    {:ok, buffer: buffer, task_sup: task_sup}
  end

  defp wait_for_tasks_to_complete(task_sup) do
    case Task.Supervisor.children(task_sup) do
      [] -> :ok
      _children ->
        Process.sleep(100)
        wait_for_tasks_to_complete(task_sup)
    end
  end

  describe "report_event/1" do
    test "reports error level events" do
      event = build_tower_event(:error, "Error event")

      assert :ok = Reporter.report_event(event)

      # Fill batch to trigger flush
      for i <- 1..49 do
        Reporter.report_event(build_tower_event(:error, "Fill #{i}"))
      end

      Process.sleep(100)

      events = TowerDB.Events.list_events()
      assert length(events) == 50
      assert Enum.any?(events, fn e ->
        match?(%RuntimeError{message: "Error event"}, e.reason)
      end)
    end

    test "reports critical level events" do
      event = build_tower_event(:critical, "Critical event")

      assert :ok = Reporter.report_event(event)

      for i <- 1..49 do
        Reporter.report_event(build_tower_event(:error, "Fill #{i}"))
      end

      Process.sleep(100)

      events = TowerDB.Events.list_events()
      assert length(events) == 50
      assert Enum.any?(events, fn e ->
        match?(%RuntimeError{message: "Critical event"}, e.reason)
      end)
    end

    test "ignores warning level events" do
      event = build_tower_event(:warning, "Warning event")

      assert :ok = Reporter.report_event(event)

      for i <- 1..50 do
        Reporter.report_event(build_tower_event(:error, "Error #{i}"))
      end

      Process.sleep(100)

      events = TowerDB.Events.list_events()
      assert length(events) == 50
      refute Enum.any?(events, fn e -> e.level == :warning end)
    end

    test "extracts all event attributes correctly" do
      stacktrace = [{__MODULE__, :test, 0, [file: ~c"test.ex", line: 1]}]
      metadata = %{request_id: "abc123", user_id: 42}

      event = %Tower.Event{
        id: "test-id",
        similarity_id: 12345,
        datetime: ~U[2026-05-08 12:00:00.000000Z],
        level: :error,
        kind: :error,
        reason: %RuntimeError{message: "Test error"},
        stacktrace: stacktrace,
        metadata: metadata,
        log_event: nil,
        plug_conn: nil,
        by: nil
      }

      Reporter.report_event(event)

      for i <- 1..49 do
        Reporter.report_event(build_tower_event(:error, "Fill #{i}"))
      end

      Process.sleep(100)

      events = TowerDB.Events.list_events()
      test_event = Enum.find(events, fn e ->
        match?(%RuntimeError{message: "Test error"}, e.reason)
      end)

      assert test_event.datetime == ~U[2026-05-08 12:00:00.000000Z]
      assert test_event.level == :error
      assert test_event.reason == %RuntimeError{message: "Test error"}
      assert test_event.stacktrace == stacktrace
      assert test_event.metadata == metadata
    end

    test "handles events with nil optional fields" do
      event = %Tower.Event{
        id: "test-id",
        similarity_id: 12345,
        datetime: DateTime.utc_now(),
        level: :error,
        kind: :error,
        reason: %RuntimeError{message: "Nil fields"},
        stacktrace: nil,
        metadata: nil,
        log_event: nil,
        plug_conn: nil,
        by: nil
      }

      Reporter.report_event(event)

      for i <- 1..49 do
        Reporter.report_event(build_tower_event(:error, "Fill #{i}"))
      end

      Process.sleep(100)

      events = TowerDB.Events.list_events()
      test_event = Enum.find(events, fn e ->
        match?(%RuntimeError{message: "Nil fields"}, e.reason)
      end)

      assert test_event.stacktrace == nil
      assert test_event.metadata == nil
    end
  end

  defp build_tower_event(level, message) do
    %Tower.Event{
      id: "test-#{System.unique_integer()}",
      similarity_id: :rand.uniform(100_000),
      datetime: DateTime.utc_now(),
      level: level,
      kind: :error,
      reason: %RuntimeError{message: message},
      stacktrace: [{__MODULE__, :test, 0, [file: ~c"test.ex", line: 1]}],
      metadata: %{},
      log_event: nil,
      plug_conn: nil,
      by: nil
    }
  end
end
