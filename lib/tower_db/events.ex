defmodule TowerDB.Events do
  import Ecto.Query

  alias TowerDB.Event
  alias TowerDB.Repo

  @default_limit 20

  def list_events(opts \\ []) do
    repo = Keyword.get(opts, :repo) || Repo.repo()
    limit = Keyword.get(opts, :limit, @default_limit)
    offset = Keyword.get(opts, :offset, 0)

    Event
    |> order_by(desc: :datetime)
    |> limit(^limit)
    |> offset(^offset)
    |> repo.all()
  end

  def count_events(opts \\ []) do
    repo = Keyword.get(opts, :repo) || Repo.repo()

    Event
    |> repo.aggregate(:count)
  end

  def get_event(id, opts \\ []) do
    repo = Keyword.get(opts, :repo) || Repo.repo()

    repo.get(Event, id)
  end

  def create_event(attrs, opts \\ []) do
    repo = Keyword.get(opts, :repo) || Repo.repo()

    delete_oldest_if_at_limit(repo, opts)

    %Event{}
    |> Event.changeset(attrs)
    |> repo.insert()
  end

  def delete_event(%Event{} = event, opts \\ []) do
    repo = Keyword.get(opts, :repo) || Repo.repo()

    repo.delete(event)
  end

  defp delete_oldest_if_at_limit(repo, opts) do
    max_events = Keyword.get(opts, :max_events) || Repo.max_events()

    if max_events do
      current_count = repo.aggregate(Event, :count)

      if current_count >= max_events do
        delete_oldest_event(repo)
      end
    end
  end

  defp delete_oldest_event(repo) do
    Event
    |> order_by(asc: :datetime)
    |> limit(1)
    |> repo.one!()
    |> repo.delete()
  end
end
