defmodule TowerDB.Migration.V01 do
  @moduledoc false

  use Ecto.Migration

  def up do
    create_if_not_exists table(:tower_db_events) do
      add :datetime, :utc_datetime_usec, null: false
      add :level, :string, null: false
      add :reason, :binary, null: false
      add :stacktrace, :binary
      add :metadata, :binary

      timestamps(type: :utc_datetime_usec)
    end

    create_if_not_exists index(:tower_db_events, [:datetime])
    create_if_not_exists index(:tower_db_events, [:level])
  end

  def down do
    drop_if_exists index(:tower_db_events, [:level])
    drop_if_exists index(:tower_db_events, [:datetime])
    drop_if_exists table(:tower_db_events)
  end
end
