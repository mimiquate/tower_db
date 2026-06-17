defmodule TowerDB.ReporterTest do
  use TowerDB.DataCase, async: false

  alias TowerDB.Reporter
  alias TowerDB.CircuitBreaker
  alias TowerDB.CircuitBreaker.Storage

  @processes [CircuitBreaker, Storage]
  @flush_delay 50

  setup do
    stop_supervisor()
    stop_processes(@processes)

    {:ok, _} = Storage.start_link()
    {:ok, _} = CircuitBreaker.start_link()

    on_exit(fn ->
      safe_call(CircuitBreaker, :reset)
      stop_processes(@processes)
    end)

    :ok
  end

  defp stop_supervisor do
    case Process.whereis(TowerDB.Supervisor) do
      nil -> :ok
      pid -> Supervisor.stop(pid)
    end
  end

  defp stop_processes(names) do
    for name <- names do
      case Process.whereis(name) do
        nil -> :ok
        pid ->
          try do
            GenServer.stop(pid, :normal, 100)
          catch
            :exit, _ -> :ok
          end
      end
    end

    Process.sleep(10)
  end

  defp safe_call(name, fun) do
    case Process.whereis(name) do
      nil -> :ok
      _pid ->
        try do
          apply(name, fun, [])
        catch
          :exit, _ -> :ok
        end
    end
  end

  describe "report_event/1" do
    test "reports error level events" do
      event = build_tower_event(:error, "Error event")

      assert :ok = Reporter.report_event(event)
      flush_and_wait()

      events = TowerDB.Events.list_events()
      assert length(events) == 1
      assert match?(%RuntimeError{message: "Error event"}, hd(events).reason)
    end

    test "reports critical level events" do
      event = build_tower_event(:critical, "Critical event")

      assert :ok = Reporter.report_event(event)
      flush_and_wait()

      events = TowerDB.Events.list_events()
      assert length(events) == 1
      assert match?(%RuntimeError{message: "Critical event"}, hd(events).reason)
    end

    test "ignores warning level events" do
      event = build_tower_event(:warning, "Warning event")

      assert :ok = Reporter.report_event(event)
      flush_and_wait()

      events = TowerDB.Events.list_events()
      assert length(events) == 0
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
      flush_and_wait()

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
      flush_and_wait()

      [db_event] = TowerDB.Events.list_events()

      assert db_event.stacktrace == nil
      assert db_event.metadata == nil
    end
  end

  defp flush_and_wait do
    Buffer.flush()
    Process.sleep(@flush_delay)
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
