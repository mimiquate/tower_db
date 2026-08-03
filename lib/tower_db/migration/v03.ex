defmodule TowerDB.Migration.V03 do
  @moduledoc false

  use Ecto.Migration

  def up do
    alter table(:tower_db_events) do
      add(:normalized_reason, :text)
    end
  end

  def down do
    alter table(:tower_db_events) do
      remove(:normalized_reason)
    end
  end
end
