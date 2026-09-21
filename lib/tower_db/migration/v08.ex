defmodule TowerDB.Migration.V08 do
  @moduledoc false

  use Ecto.Migration

  def up do
    alter table(:tower_db_events) do
      add(:request_data, :map)
    end
  end

  def down do
    alter table(:tower_db_events) do
      remove(:request_data)
    end
  end
end
