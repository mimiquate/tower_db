defmodule TowerDB.Migration.V01 do
  @moduledoc false

  use Ecto.Migration

  def up do
    create_if_not_exists table(:tower_db_events) do
      add :similarity_id, :bigint, null: false
      add :datetime, :utc_datetime_usec, null: false
      add :level, :string, null: false
      add :kind, :string, null: false
      add :reason, :binary, null: false
      add :stacktrace, :binary
      add :log_event, :binary
      add :plug_conn, :binary
      add :metadata, :binary
      add :by, :string

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
