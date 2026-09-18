defmodule TowerDB.PrunerTest do
  use TowerDB.DataCase, async: false

  alias TowerDB.Events
  alias TowerDB.Pruner

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

  # Starts the pruner with a long interval so its timer never fires on its own,
  # then triggers a single prune cycle synchronously: `:sys.get_state/1` only
  # replies once every message queued ahead of it - including our `:prune` -
  # has been handled.
  defp prune(opts) do
    {:ok, pid} = Pruner.start_link(Keyword.put_new(opts, :interval, {999_999, :seconds}))
    on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)

    send(pid, :prune)
    :sys.get_state(pid)
    :ok
  end

  test "deletes events older than max_age and keeps the rest" do
    now = DateTime.utc_now()
    old = insert_event(datetime: DateTime.add(now, -200, :second))
    recent = insert_event(datetime: DateTime.add(now, -10, :second))

    prune(max_age: {100, :seconds})

    assert ids_of(Events.list_events(limit: 100)) == ids_of([recent])
    refute old.id in ids_of(Events.list_events(limit: 100))
  end

  test "keeps only the newest max_size_per_issue events per issue" do
    now = DateTime.utc_now()

    e1 = insert_event(similarity_id: 1, datetime: DateTime.add(now, -300, :second))
    e2 = insert_event(similarity_id: 1, datetime: DateTime.add(now, -200, :second))
    e3 = insert_event(similarity_id: 1, datetime: DateTime.add(now, -100, :second))
    e4 = insert_event(similarity_id: 1, datetime: now)
    other = insert_event(similarity_id: 2, datetime: DateTime.add(now, -500, :second))

    prune(max_size_per_issue: 2, max_age: {999_999_999, :seconds})

    remaining = ids_of(Events.list_events(limit: 100))
    assert remaining == ids_of([e3, e4, other])
    refute e1.id in remaining
    refute e2.id in remaining
  end

  test "keeps only the newest max_size events overall, batching the deletes" do
    now = DateTime.utc_now()

    events =
      for i <- 1..10 do
        insert_event(similarity_id: i, datetime: DateTime.add(now, -(10 - i), :second))
      end

    kept = Enum.take(events, -2)

    prune(max_size: 2, batch_size: 2, max_age: {999_999_999, :seconds})

    assert ids_of(Events.list_events(limit: 100)) == ids_of(kept)
  end
end
