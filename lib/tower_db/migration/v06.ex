defmodule TowerDB.Migration.V06 do
  @moduledoc false

  use Ecto.Migration

  def up do
    create(index(:tower_db_events, [:similarity_id, "datetime DESC"]))
  end

  def down do
    drop(index(:tower_db_events, [:similarity_id, "datetime DESC"]))
  end
end
