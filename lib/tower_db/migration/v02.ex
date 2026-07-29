defmodule TowerDB.Migration.V02 do
  @moduledoc false

  use Ecto.Migration

  def up do
    alter table(:tower_db_events) do
      add_if_not_exists :similarity_id, :bigint
      add_if_not_exists :kind, :string
      add_if_not_exists :log_event, :binary
      add_if_not_exists :plug_conn, :binary
      add_if_not_exists :by, :string
    end
  end

  def down do
    alter table(:tower_db_events) do
      remove_if_exists :by, :string
      remove_if_exists :plug_conn, :binary
      remove_if_exists :log_event, :binary
      remove_if_exists :kind, :string
      remove_if_exists :similarity_id, :bigint
    end
  end
end
