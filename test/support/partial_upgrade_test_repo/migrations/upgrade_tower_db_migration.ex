defmodule TowerDB.PartialUpgradeTestRepo.Migrations.UpgradeTowerDB do
  use Ecto.Migration

  def up, do: TowerDB.Migration.up(from: 2, to: 4)
  def down, do: TowerDB.Migration.down(from: 4, to: 2)
end
