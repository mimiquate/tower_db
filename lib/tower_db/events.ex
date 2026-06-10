defmodule TowerDB.Events do
  import Ecto.Query

  alias TowerDB.Event
  alias TowerDB.Repo

  @cache_table :tower_db_events_cache

  def list_events(opts \\ []) do
    repo = Keyword.get(opts, :repo) || Repo.repo()

    try do
      events =
        Event
        |> order_by(desc: :datetime)
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

  def create_event(attrs, opts \\ []) do
    repo = Keyword.get(opts, :repo) || Repo.repo()

    case %Event{}
         |> Event.changeset(attrs)
         |> repo.insert() do
      {:ok, event} = result ->
        add_event_to_cache(event)
        result

      error ->
        error
    end
  end

  # Cache functions

  defp cache_events(events) do
    ensure_cache_table()
    :ets.insert(@cache_table, {:events, events})
  end

  defp add_event_to_cache(event) do
    ensure_cache_table()
    cached = get_cached_events()
    # Prepend new event (list is ordered by datetime desc)
    :ets.insert(@cache_table, {:events, [event | cached]})
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
end
