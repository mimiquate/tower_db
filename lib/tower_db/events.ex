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

  @doc """
  Insert multiple events in a single transaction using Ecto.Multi.

  Returns `{:ok, count}` on success or `{:error, changeset}` on failure.
  """
  def create_events_batch(attrs_list, opts \\ []) do
    repo = Keyword.get(opts, :repo) || Repo.repo()

    multi =
      attrs_list
      |> Enum.with_index()
      |> Enum.reduce(Ecto.Multi.new(), fn {attrs, index}, multi ->
        changeset = Event.changeset(%Event{}, attrs)
        Ecto.Multi.insert(multi, :"event_#{index}", changeset)
      end)

    case repo.transaction(multi) do
      {:ok, results} ->
        events = Map.values(results)
        add_events_to_cache(events)
        {:ok, map_size(results)}

      {:error, _failed_op, changeset, _changes} ->
        {:error, changeset}
    end
  end

  # Cache functions (ETS table created in application.ex)

  defp cache_events(events) do
    :ets.insert(@cache_table, {:events, events})
  end

  defp add_event_to_cache(event) do
    cached = get_cached_events()
    # Prepend new event (list is ordered by datetime desc)
    :ets.insert(@cache_table, {:events, [event | cached]})
  end

  defp add_events_to_cache(events) when is_list(events) do
    cached = get_cached_events()
    # Prepend new events (sorted by datetime desc)
    sorted = Enum.sort_by(events, & &1.datetime, {:desc, DateTime})
    :ets.insert(@cache_table, {:events, sorted ++ cached})
  end

  defp get_cached_events do
    case :ets.lookup(@cache_table, :events) do
      [{:events, events}] -> events
      [] -> []
    end
  end
end
