defmodule TowerDB.Migration.V04 do
  @moduledoc false

  use Ecto.Migration

  def up do
    execute("CREATE EXTENSION IF NOT EXISTS pg_trgm")

    create_if_not_exists(index(:tower_db_events, ["normalized_reason gin_trgm_ops"], using: :gin))
  end

  def down do
    drop_if_exists(index(:tower_db_events, ["normalized_reason gin_trgm_ops"], using: :gin))
  end
end
