defmodule TowerDB.Events do
  import Ecto.Query

  alias TowerDB.Event
  alias TowerDB.Repo

  @cache_table :tower_db_events_cache

  @default_limit 20

  def list_events(opts \\ []) do
    repo = Keyword.get(opts, :repo) || Repo.repo()
    limit = Keyword.get(opts, :limit, @default_limit)
    offset = Keyword.get(opts, :offset, 0)

    try do
      events =
        Event
        |> order_by(desc: :id)
        |> limit(^limit)
        |> repo.all()

      # Cache successful result
      cache_events(events)
      events
    rescue
      _e ->
        # Database unavailable, return cached events
        get_cached_events()
    catch
      :exit, _reason ->
        get_cached_events()
    end
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

    %Event{}
    |> Event.changeset(attrs)
    |> repo.insert()
  end

  # Cache functions

  defp cache_events(events) do
    ensure_cache_table()
    :ets.insert(@cache_table, {:events, events})
  end

  defp get_cached_events do
    ensure_cache_table()

    case :ets.lookup(@cache_table, :events) do
      [{:events, events}] -> events
      [] -> []
    end
  end

  defp ensure_cache_table do
    case :ets.info(@cache_table) do
      :undefined ->
        :ets.new(@cache_table, [:set, :named_table, :public, read_concurrency: true])

      _ ->
        :ok
    end
  end

  def delete_event(%Event{} = event, opts \\ []) do
    repo = Keyword.get(opts, :repo) || Repo.repo()

    repo.delete(event)
  end
end
