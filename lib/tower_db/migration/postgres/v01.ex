defmodule TowerDB.Migration.Postgres.V01 do
  @moduledoc false

  use Ecto.Migration

  def up(%{prefix: prefix, create_schema: create_schema?}) do
    if create_schema?, do: execute("CREATE SCHEMA IF NOT EXISTS #{prefix}")

    create_if_not_exists table(:tower_db_meta, prefix: prefix, primary_key: false) do
      add :key, :string, primary_key: true
      add :value, :string

      timestamps(type: :utc_datetime_usec)
    end

    create_if_not_exists table(:tower_db_events, prefix: prefix) do
      add :datetime, :utc_datetime_usec, null: false
      add :level, :string, null: false
      add :reason, :binary, null: false
      add :stacktrace, :binary
      add :metadata, :binary

      timestamps(type: :utc_datetime_usec)
    end

    create_if_not_exists index(:tower_db_events, [:datetime], prefix: prefix)
    create_if_not_exists index(:tower_db_events, [:level], prefix: prefix)
  end

  def down(%{prefix: prefix}) do
    drop_if_exists index(:tower_db_events, [:level], prefix: prefix)
    drop_if_exists index(:tower_db_events, [:datetime], prefix: prefix)
    drop_if_exists table(:tower_db_events, prefix: prefix)
    drop_if_exists table(:tower_db_meta, prefix: prefix)
  end
end
