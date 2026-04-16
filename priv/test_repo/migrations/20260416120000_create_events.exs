defmodule TowerDB.TestRepo.Migrations.CreateEvents do
  use Ecto.Migration

  def change do
    create table(:events) do
      add :datetime, :utc_datetime_usec, null: false
      add :level, :string, null: false
      add :reason, :binary, null: false
      add :stacktrace, :binary
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:events, [:datetime])
    create index(:events, [:level])
  end
end
