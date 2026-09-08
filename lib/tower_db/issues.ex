defmodule TowerDB.Issues do
  import Ecto.Query

  alias TowerDB.Event
  alias TowerDB.Issue
  alias TowerDB.Repo

  @default_limit 20

  def list_issues(opts \\ []) do
    repo = Keyword.get(opts, :repo) || Repo.repo()
    filters = Keyword.get(opts, :filters, [])
    limit = Keyword.get(opts, :limit, @default_limit)
    offset = Keyword.get(opts, :offset, 0)

    {datetime_range, event_filters} = Keyword.pop(filters, :datetime_range)

    ordered_ids =
      Event
      |> where(^filter_where(event_filters))
      |> group_by([e], e.similarity_id)
      |> having(^last_seen_in_range(datetime_range))
      |> order_by([e], desc: max(e.datetime))
      |> limit(^limit)
      |> offset(^offset)
      |> select([e], e.similarity_id)
      |> repo.all()

    issues_by_id =
      Event
      |> where([e], e.similarity_id in ^ordered_ids)
      |> distinct([e], e.similarity_id)
      |> order_by([e], asc: e.similarity_id, desc: e.datetime)
      |> select([e], %Issue{
        id: e.similarity_id,
        count_events: over(count(e.id), partition_by: e.similarity_id),
        first_seen: over(min(e.datetime), partition_by: e.similarity_id),
        last_seen: over(max(e.datetime), partition_by: e.similarity_id),
        last_event: e
      })
      |> repo.all()
      |> Map.new(&{&1.id, &1})

    Enum.map(ordered_ids, &Map.fetch!(issues_by_id, &1))
  end

  def get_issue(id, opts \\ []) do
    opts
    |> Keyword.put(:filters, similarity_id: id)
    |> list_issues()
    |> List.first()
  end

  def count_issues(opts \\ []) do
    repo = Keyword.get(opts, :repo) || Repo.repo()
    filters = Keyword.get(opts, :filters, [])

    {datetime_range, event_filters} = Keyword.pop(filters, :datetime_range)

    Event
    |> where(^filter_where(event_filters))
    |> group_by([e], e.similarity_id)
    |> having(^last_seen_in_range(datetime_range))
    |> select([e], e.similarity_id)
    |> subquery()
    |> select(count("*"))
    |> repo.one()
  end

  defp filter_where(filters) do
    Enum.reduce(filters, dynamic(true), fn
      {:search, value}, dynamic when value != "" ->
        search_term = "%#{value}%"
        dynamic([e], ^dynamic and ilike(e.normalized_reason, ^search_term))

      {:level, value}, dynamic when not is_nil(value) ->
        dynamic([e], ^dynamic and e.level == ^value)

      {:similarity_id, value}, dynamic
      when is_binary(value) or is_list(value) or is_integer(value) ->
        value = List.wrap(value)
        dynamic([e], ^dynamic and e.similarity_id in ^value)

      {_, _}, dynamic ->
        dynamic
    end)
  end

  defp last_seen_in_range(nil), do: dynamic(true)

  defp last_seen_in_range({from, to}) do
    dynamic([e], max(e.datetime) >= ^from and max(e.datetime) <= ^to)
  end
end
