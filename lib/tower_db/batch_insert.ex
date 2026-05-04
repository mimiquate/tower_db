defmodule TowerDB.BatchInsert do
  @moduledoc false

  alias TowerDB.Event
  alias TowerDB.Repo

  require Logger

  def insert_all([]), do: {:ok, 0}

  def insert_all(events_attrs) when is_list(events_attrs) do
    repo = Repo.repo()

    multi =
      events_attrs
      |> Enum.with_index()
      |> Enum.reduce(Ecto.Multi.new(), fn {attrs, index}, multi ->
        changeset = Event.changeset(%Event{}, attrs)
        Ecto.Multi.insert(multi, {:event, index}, changeset)
      end)

    case repo.transaction(multi) do
      {:ok, results} ->
        {:ok, map_size(results)}

      {:error, _name, changeset, _changes} ->
        Logger.error("[TowerDB] Batch insert error: #{inspect(changeset.errors)}")
        {:error, changeset}
    end
  end
end
