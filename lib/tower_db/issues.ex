defmodule TowerDB.Issues do
  import Ecto.Query

  alias TowerDB.Event
  alias TowerDB.Issue
  alias TowerDB.Repo

  @default_limit 20
  @occurrences_window_days 30

  def list_issues(opts \\ []) do
    repo = Keyword.get(opts, :repo) || Repo.repo()
    filters = Keyword.get(opts, :filters, [])
    limit = Keyword.get(opts, :limit, @default_limit)
    offset = Keyword.get(opts, :offset, 0)
    occurrences_since = DateTime.add(DateTime.utc_now(), -@occurrences_window_days, :day)

    matching_similarity_ids =
      Event
      |> where(^filter_where(filters))
      |> select([e], e.similarity_id)
      |> distinct(true)

    issue_data =
      Event
      |> where([e], e.similarity_id in subquery(matching_similarity_ids))
      |> where([e], e.datetime >= ^occurrences_since)
      |> distinct([e], e.similarity_id)
      |> order_by([e], asc: e.similarity_id, desc: e.datetime)
      |> select([e], %{
        similarity_id: e.similarity_id,
        last_event_id: e.id,
        count_events: over(count(e.id), partition_by: e.similarity_id),
        first_seen: over(min(e.datetime), partition_by: e.similarity_id),
        last_seen: over(max(e.datetime), partition_by: e.similarity_id)
      })
      |> subquery()

    Event
    |> join(:inner, [e], issue in ^issue_data, on: issue.last_event_id == e.id)
    |> order_by([_e, issue], desc: issue.last_seen)
    |> limit(^limit)
    |> offset(^offset)
    |> select([e, issue], %Issue{
      id: issue.similarity_id,
      count_events: issue.count_events,
      first_seen: issue.first_seen,
      last_seen: issue.last_seen,
      last_event: e
    })
    |> repo.all()
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

    Event
    |> where(^filter_where(filters))
    |> select([e], count(e.similarity_id, :distinct))
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

      {:datetime_range, {from, to}}, dynamic ->
        dynamic([e], ^dynamic and e.datetime >= ^from and e.datetime <= ^to)

      {_, _}, dynamic ->
        dynamic
    end)
  end
end
