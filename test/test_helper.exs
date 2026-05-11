{:ok, _} = TowerDB.TestRepo.start_link()

# Start processes needed for tests
Task.Supervisor.start_link(name: TowerDB.TaskSupervisor, max_children: 5)
TowerDB.Buffer.start_link()

# Run migrations once
TowerDB.TestHelpers.run_migration(:up)

ExUnit.start()

Ecto.Adapters.SQL.Sandbox.mode(TowerDB.TestRepo, :manual)
