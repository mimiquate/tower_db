defmodule TowerDB.Pruner do
  import Ecto.Query

  alias TowerDB.Event
  alias TowerDB.Events

  @default_max_age 7_776_000
  @default_max_size 100_000
  @default_max_size_per_issue 1_000
  @default_interval 30
  @default_batch_size 1_000

  defp config(key, default) do
    :tower_db
    |> Application.get_env(:pruner, [])
    |> Keyword.get(key, default)
  end

  defp max_age, do: config(:max_age, @default_max_age)
  defp max_size, do: config(:max_size, @default_max_size)
  defp max_size_per_issue, do: config(:max_size_per_issue, @default_max_size_per_issue)
  defp interval, do: config(:interval, @default_interval)
  defp batch_size, do: config(:batch_size, @default_batch_size)

  defp prune_by_age(repo) do
    cutoff = DateTime.add(DateTime.utc_now(), -max_age(), :second)
    delete_older_than(repo, cutoff)
  end

  defp delete_older_than(repo, cutoff) do
    ids =
      Event
      |> where([e], e.datetime < ^cutoff)
      |> order_by(asc: :datetime)
      |> limit(^batch_size())
      |> select([e], e.id)
      |> repo.all()

    case ids do
      [] ->
        :ok

      ids ->
        Events.delete_events(ids, repo: repo)
        delete_older_than(repo, cutoff)
    end
  end
end
