defmodule TowerDB.CleanupServerTest do
  use TowerDB.DataCase, async: false

  alias TowerDB.CleanupServer
  alias TowerDB.Events

  describe "init/1 validation" do
    test "raises error when cleanup_strategy is :automatic without options" do
      assert_raise ArgumentError, ~r/Invalid cleanup_strategy/, fn ->
        CleanupServer.init(cleanup_strategy: :automatic)
      end
    end

    test "raises error when cleanup_strategy is {:automatic} without options" do
      assert_raise ArgumentError, ~r/Invalid cleanup_strategy/, fn ->
        CleanupServer.init(cleanup_strategy: {:automatic})
      end
    end

    test "raises error when older_than is missing" do
      assert_raise ArgumentError, ~r/requires :older_than option/, fn ->
        CleanupServer.init(cleanup_strategy: {:automatic, run_every: 5})
      end
    end

    test "raises error when run_every is missing" do
      assert_raise ArgumentError, ~r/requires :run_every option/, fn ->
        CleanupServer.init(cleanup_strategy: {:automatic, older_than: 90})
      end
    end

    test "raises error when both older_than and run_every are missing" do
      assert_raise ArgumentError, ~r/requires both :older_than and :run_every/, fn ->
        CleanupServer.init(cleanup_strategy: {:automatic, []})
      end
    end

    test "returns :ignore when cleanup_strategy is nil" do
      assert :ignore == CleanupServer.init(cleanup_strategy: nil)
    end

    test "returns :ignore when cleanup_strategy is :manual" do
      assert :ignore == CleanupServer.init(cleanup_strategy: :manual)
    end

    test "starts successfully with valid automatic config" do
      result = CleanupServer.init(cleanup_strategy: {:automatic, older_than: 90, run_every: 5})

      assert {:ok, state} = result
      assert state.older_than == 90
      assert state.interval_ms == 5 * 24 * 60 * 60 * 1000
    end
  end

  describe "handle_info/2" do
    test "cleanup message prunes old events" do
      now = DateTime.utc_now()

      {:ok, _} = Events.create_event(%{datetime: DateTime.add(now, -60, :day), level: :error, reason: "old_event"})
      {:ok, _} = Events.create_event(%{datetime: DateTime.add(now, -5, :day), level: :error, reason: "recent_event"})

      assert length(Events.list_events()) == 2

      state = %{older_than: 30, interval_ms: 1000, repo: nil}
      {:noreply, _new_state} = CleanupServer.handle_info(:cleanup, state)

      events = Events.list_events()
      assert length(events) == 1
      assert hd(events).reason == "recent_event"
    end
  end
end
