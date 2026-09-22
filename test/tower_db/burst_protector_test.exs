defmodule TowerDB.BurstProtectorTest do
  use TowerDB.DataCase, async: false

  alias TowerDB.BurstProtector
  import ExUnit.CaptureLog, only: [capture_log: 2]

  defp start(opts) do
    Supervisor.terminate_child(TowerDB.Supervisor, BurstProtector)
    {:ok, pid} = BurstProtector.start_link(Keyword.put_new(opts, :interval, 999_999))

    on_exit(fn ->
      if Process.alive?(pid), do: GenServer.stop(pid)
      Supervisor.restart_child(TowerDB.Supervisor, BurstProtector)
    end)

    pid
  end

  defp event_attrs do
    %{
      id: UUIDv7.generate(),
      similarity_id: 1,
      datetime: DateTime.utc_now(),
      level: :error,
      kind: :error,
      reason: %RuntimeError{message: "boom"}
    }
  end

  test "drops events once max_count is reached, then resets the count on the next window" do
    pid = start(max_count: 3)

    capture_log([level: :warning], fn ->
      results = for _ <- 1..5, do: BurstProtector.add(event_attrs())

      {added, dropped} = Enum.split(results, 3)
      assert Enum.all?(added, &match?({:ok, _event}, &1))
      assert Enum.all?(dropped, &(&1 == :dropped))

      assert %{count: 3} = :sys.get_state(pid)
      send(pid, :reset)
      assert %{count: 0} = :sys.get_state(pid)
    end)
  end
end
