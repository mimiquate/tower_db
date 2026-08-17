defmodule TowerDB.TestRepo.Migrations.AddTowerDB do
  use Ecto.Migration

  def up, do: TowerDB.Migration.up(from: 0, to: 5)
  def down, do: TowerDB.Migration.down(from: 5, to: 0)
end
