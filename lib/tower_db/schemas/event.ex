defmodule TowerDB.Event do
  use Ecto.Schema

  import Ecto.Changeset

  schema "tower_db_events" do
    field :datetime, :utc_datetime_usec
    field :level, Ecto.Enum, values: [:debug, :info, :emergency, :alert, :critical, :error, :warning, :notice]
    field :reason, TowerDB.Types.Term
    field :stacktrace, TowerDB.Types.Term
    field :metadata, TowerDB.Types.Term

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(event, attrs) do
    event
    |> cast(attrs, [:datetime, :level, :reason, :stacktrace, :metadata])
    |> validate_required([:datetime, :level, :reason])
  end
end
