defmodule TowerDB.PartialUpgradeTestRepo.Migrations.UpgradeTowerDB do
  use Ecto.Migration

  def up, do: TowerDB.Migration.up(from: 2, to: 8)
  def down, do: TowerDB.Migration.down(from: 8, to: 2)
end
