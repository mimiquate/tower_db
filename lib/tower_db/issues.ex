defmodule TowerDB.Issues do
  import Ecto.Query

  alias TowerDB.Event
  alias TowerDB.Issue
  alias TowerDB.Repo

  def list_issues(opts \\ []) do
    repo = Keyword.get(opts, :repo) || Repo.repo()

    Event
    |> distinct([e], e.similarity_id)
    |> order_by([e], asc: e.similarity_id, desc: e.datetime)
    |> select([e], %Issue{
      similarity_id: e.similarity_id,
      count_occurrences: over(count(e.id), partition_by: e.similarity_id),
      first_seen: over(min(e.datetime), partition_by: e.similarity_id),
      last_seen: over(max(e.datetime), partition_by: e.similarity_id),
      last_event: e
    })
    |> repo.all()
  end
end
