{:ok, _} = TowerDB.TestRepo.start_link()

# Run migrations once
TowerDB.TestHelpers.run_migration(:up)

ExUnit.start()

Ecto.Adapters.SQL.Sandbox.mode(TowerDB.TestRepo, :manual)
