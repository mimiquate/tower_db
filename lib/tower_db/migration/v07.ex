defmodule TowerDB.Migration.V07 do
  @moduledoc false

  use Ecto.Migration

  def up do
    alter table(:tower_db_events) do
      remove(:reason)
    end
  end

  def down do
    alter table(:tower_db_events) do
      add(:reason, :binary)
    end
  end
end
