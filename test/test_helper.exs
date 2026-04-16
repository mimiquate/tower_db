{:ok, _} = TowerDB.TestRepo.start_link()

ExUnit.start()

Ecto.Adapters.SQL.Sandbox.mode(TowerDB.TestRepo, :manual)
