defmodule TowerDB.TestRepo.Migrations.AddTowerDB do
  use Ecto.Migration

  def up, do: TowerDB.Migration.up(from: 0, to: 4)
  def down, do: TowerDB.Migration.down(from: 4, to: 0)
end
