defmodule TowerDB.Events do
  import Ecto.Query

  alias TowerDB.Event
  alias TowerDB.Repo

  @default_limit 20

  def list_events(opts \\ []) do
    repo = Keyword.get(opts, :repo) || Repo.repo()
    filters = Keyword.get(opts, :filters, [])
    limit = Keyword.get(opts, :limit, @default_limit)
    offset = Keyword.get(opts, :offset, 0)
    search = Keyword.get(filters, :search, "")

    if search == "" do
      Event
      |> order_by(desc: :datetime)
      |> limit(^limit)
      |> offset(^offset)
      |> repo.all()
    else
      Event
      |> order_by(desc: :datetime)
      |> repo.all()
      |> maybe_filter_by_search(search)
      |> Enum.drop(offset)
      |> Enum.take(limit)
    end
  end

  defp maybe_filter_by_search(events, ""), do: events

  defp maybe_filter_by_search(events, search) do
    search = String.downcase(search)

    Enum.filter(events, fn event ->
      event.reason
      |> format_reason()
      |> String.downcase()
      |> String.contains?(search)
    end)
  end

  defp format_reason(reason) when is_exception(reason), do: Exception.message(reason)
  defp format_reason(reason) when is_binary(reason), do: reason
  defp format_reason(reason), do: inspect(reason)

  def count_events(opts \\ []) do
    repo = Keyword.get(opts, :repo) || Repo.repo()
    filters = Keyword.get(opts, :filters, [])
    search = Keyword.get(filters, :search, "")

    if search == "" do
      Event
      |> repo.aggregate(:count)
    else
      # When filtering by search, we need to count in-memory
      # since the reason field is serialized
      Event
      |> repo.all()
      |> maybe_filter_by_search(search)
      |> length()
    end
  end

  def get_event(id, opts \\ []) do
    repo = Keyword.get(opts, :repo) || Repo.repo()

    repo.get(Event, id)
  end

  def create_event(attrs, opts \\ []) do
    repo = Keyword.get(opts, :repo) || Repo.repo()

    %Event{}
    |> Event.changeset(attrs)
    |> repo.insert()
  end

  def delete_event(%Event{} = event, opts \\ []) do
    repo = Keyword.get(opts, :repo) || Repo.repo()

    repo.delete(event)
  end
end
