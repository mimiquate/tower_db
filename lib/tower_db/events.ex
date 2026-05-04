defmodule TowerDB.Events do
  import Ecto.Query

  alias TowerDB.Event
  alias TowerDB.Repo

  def list_events(opts \\ []) do
    repo = Keyword.get(opts, :repo) || Repo.repo()

    Event
    |> order_by(desc: :datetime)
    |> repo.all()
  end

  def create_event(attrs, opts \\ []) do
    repo = Keyword.get(opts, :repo) || Repo.repo()

    %Event{}
    |> Event.changeset(attrs)
    |> repo.insert()
  end
end
