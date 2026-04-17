defmodule TowerDB.Events do
  alias TowerDB.Event
  alias TowerDB.Repo

  def create_event(attrs) do
    %Event{}
    |> Event.changeset(attrs)
    |> Repo.repo().insert()
  end
end
