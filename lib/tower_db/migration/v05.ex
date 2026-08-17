defmodule TowerDB.Migration.V05 do
  @moduledoc false

  use Ecto.Migration

  def up do
    alter table(:tower_db_events) do
      remove_if_exists(:log_event, :binary)
      remove_if_exists(:plug_conn, :binary)
      remove_if_exists(:by, :string)
    end
  end

  def down do
    alter table(:tower_db_events) do
      add_if_not_exists(:by, :string)
      add_if_not_exists(:plug_conn, :binary)
      add_if_not_exists(:log_event, :binary)
    end
  end
end
