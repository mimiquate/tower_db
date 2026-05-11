defmodule TowerDB.TestHelpers do
  @moduledoc false

  def run_migration(direction) do
    Ecto.Migrator.run(
      TowerDB.TestRepo,
      [{0, TowerDB.TestRepo.Migrations.CreateEvents}],
      direction,
      all: true
    )
  end
end
