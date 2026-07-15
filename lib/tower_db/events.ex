defmodule TowerDB.Events do
  import Ecto.Query

  alias TowerDB.Event
  alias TowerDB.Repo

  @default_limit 20

  def list_events(opts \\ []) do
    repo = Keyword.get(opts, :repo) || Repo.repo()
    limit = Keyword.get(opts, :limit, @default_limit)
    offset = Keyword.get(opts, :offset, 0)

    with_db_protection(fn ->
      Event
      |> order_by(desc: :datetime)
      |> limit(^limit)
      |> offset(^offset)
      |> repo.all()
    end)
  end

  def count_events(opts \\ []) do
    repo = Keyword.get(opts, :repo) || Repo.repo()

    with_db_protection(fn ->
      Event
      |> repo.aggregate(:count)
    end)
  end

  def get_event(id, opts \\ []) do
    repo = Keyword.get(opts, :repo) || Repo.repo()

    with_db_protection(fn ->
      repo.get(Event, id)
    end)
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

  defp with_db_protection(fun) do
    if db_unavailable?() do
      {:error, :database_unavailable}
    else
      try do
        {:ok, fun.()}
      rescue
        _e -> {:error, :database_unavailable}
      catch
        :exit, _reason -> {:error, :database_unavailable}
      end
    end
  end

  defp db_unavailable? do
    TowerDB.CircuitBreaker.state().state == :open
  catch
    :exit, _ -> true
  end
end
