{:ok, _} = TowerDB.TestRepo.start_link()
{:ok, _} = TowerDB.PartialUpgradeTestRepo.start_link()

# Run migrations once
TowerDB.TestHelpers.run_migration(:up)

ExUnit.start()

Ecto.Adapters.SQL.Sandbox.mode(TowerDB.TestRepo, :manual)
Ecto.Adapters.SQL.Sandbox.mode(TowerDB.PartialUpgradeTestRepo, :manual)
