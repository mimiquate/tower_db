defmodule TowerDB.BurstProtectorTest do
  use TowerDB.DataCase, async: false

  alias TowerDB.BurstProtector

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

  test "drops events once max_count is reached" do
    start(max_count: 3)

    results = for _ <- 1..5, do: BurstProtector.add(event_attrs())

    {added, dropped} = Enum.split(results, 3)
    assert Enum.all?(added, &match?({:ok, _event}, &1))
    assert Enum.all?(dropped, &(&1 == :dropped))
  end
end
