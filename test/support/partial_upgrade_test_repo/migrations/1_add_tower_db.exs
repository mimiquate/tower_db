defmodule TowerDB.PartialUpgradeTestRepo.Migrations.AddTowerDB do
  use Ecto.Migration

  def up, do: TowerDB.Migration.up(from: 0, to: 2)
  def down, do: TowerDB.Migration.down(from: 2, to: 0)
end
