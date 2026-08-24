defmodule TowerDB.Migration.V06 do
  @moduledoc false

  use Ecto.Migration

  def up do
    create_if_not_exists(index(:tower_db_events, [:similarity_id]))
  end

  def down do
    drop_if_exists(index(:tower_db_events, [:similarity_id]))
  end
end
