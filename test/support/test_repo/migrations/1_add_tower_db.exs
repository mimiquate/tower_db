defmodule TowerDB.TestRepo.Migrations.AddTowerDB do
  use Ecto.Migration

  def up, do: TowerDB.Migration.up(from: 0, to: 7)
  def down, do: TowerDB.Migration.down(from: 7, to: 0)
end
