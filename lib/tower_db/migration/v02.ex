defmodule TowerDB.Migration.V02 do
  @moduledoc false

  use Ecto.Migration

  def up do
    alter table(:tower_db_events) do
      add :similarity_id, :bigint
      add :kind, :string
      add :log_event, :binary
      add :plug_conn, :binary
      add :by, :string
    end
  end

  def down do
    alter table(:tower_db_events) do
      remove :by
      remove :plug_conn
      remove :log_event
      remove :kind
      remove :similarity_id
    end
  end
end
