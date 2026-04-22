defmodule TowerDB.Events do
  alias TowerDB.Event
  alias TowerDB.Repo

  def create_event(attrs, opts \\ []) do
    repo = Keyword.get(opts, :repo) || Repo.repo()

    %Event{}
    |> Event.changeset(attrs)
    |> repo.insert()
  end
end
