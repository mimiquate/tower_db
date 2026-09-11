defmodule TowerDB.PrunerTest do
  use TowerDB.DataCase, async: false

  alias TowerDB.Events
  alias TowerDB.Pruner

  setup do
    on_exit(fn -> Application.delete_env(:tower_db, :pruner) end)
    :ok
  end

  defp configure_pruner(overrides) do
    defaults = [
      max_age: {999_999_999, :seconds},
      max_size: :infinity,
      max_size_per_issue: :infinity,
      interval: {30, :seconds},
      batch_size: 1_000
    ]

    Application.put_env(:tower_db, :pruner, Keyword.merge(defaults, overrides))
  end

  defp insert_event(overrides) do
    attrs =
      Map.merge(
        %{
          id: UUIDv7.generate(),
          similarity_id: 1,
          datetime: DateTime.utc_now(),
          level: :error,
          kind: :error,
          reason: %RuntimeError{message: "boom"}
        },
        Map.new(overrides)
      )

    {:ok, event} = Events.create_event(attrs)
    event
  end

  defp ids_of(events), do: events |> Enum.map(& &1.id) |> Enum.sort()

  test "prune/1 deletes events older than max_age and keeps the rest" do
    configure_pruner(max_age: {100, :seconds})

    now = DateTime.utc_now()
    old = insert_event(datetime: DateTime.add(now, -200, :second))
    recent = insert_event(datetime: DateTime.add(now, -10, :second))

    Pruner.prune()

    assert ids_of(Events.list_events(limit: 100)) == ids_of([recent])
    refute old.id in ids_of(Events.list_events(limit: 100))
  end

  test "prune/1 keeps only the newest max_size_per_issue events per issue" do
    configure_pruner(max_size_per_issue: 2)

    now = DateTime.utc_now()

    e1 = insert_event(similarity_id: 1, datetime: DateTime.add(now, -300, :second))
    e2 = insert_event(similarity_id: 1, datetime: DateTime.add(now, -200, :second))
    e3 = insert_event(similarity_id: 1, datetime: DateTime.add(now, -100, :second))
    e4 = insert_event(similarity_id: 1, datetime: now)
    other = insert_event(similarity_id: 2, datetime: DateTime.add(now, -500, :second))

    Pruner.prune()

    remaining = ids_of(Events.list_events(limit: 100))
    assert remaining == ids_of([e3, e4, other])
    refute e1.id in remaining
    refute e2.id in remaining
  end

  test "prune/1 keeps only the newest max_size events overall, batching the deletes" do
    configure_pruner(max_size: 2, batch_size: 2)

    now = DateTime.utc_now()

    events =
      for i <- 1..10 do
        insert_event(similarity_id: i, datetime: DateTime.add(now, -(10 - i), :second))
      end

    kept = Enum.take(events, -2)

    Pruner.prune()

    assert ids_of(Events.list_events(limit: 100)) == ids_of(kept)
  end

  test "start_link/1 schedules pruning and the timer triggers it" do
    configure_pruner(max_age: {100, :seconds}, interval: {0, :seconds})

    old = insert_event(datetime: DateTime.add(DateTime.utc_now(), -200, :second))

    {:ok, pid} = Pruner.start_link()
    on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)

    Process.sleep(50)

    refute old.id in ids_of(Events.list_events(limit: 100))
  end
end
