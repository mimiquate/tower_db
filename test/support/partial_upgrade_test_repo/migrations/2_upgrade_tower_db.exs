defmodule TowerDB.PartialUpgradeTestRepo.Migrations.UpgradeTowerDB do
  use Ecto.Migration

  def up, do: TowerDB.Migration.up(from: 2, to: 7)
  def down, do: TowerDB.Migration.down(from: 7, to: 2)
end
