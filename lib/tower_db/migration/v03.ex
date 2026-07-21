defmodule TowerDB.Migration.V03 do
  @moduledoc false

  use Ecto.Migration

  def up do
    alter table(:tower_db_events) do
      add(:normalized_reason, :text)
    end

    create_if_not_exists(index(:tower_db_events, [:normalized_reason]))
  end

  def down do
    drop_if_exists index(:tower_db_events, [:normalized_reason])

    alter table(:tower_db_events) do
      remove(:normalized_reason)
    end
  end
end
