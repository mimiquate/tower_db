{:ok, _} = TowerDB.TestRepo.start_link()

# Run migrations once
TowerDB.TestHelpers.run_migration(:up)

# Create the events cache table if not already created by application.ex
case :ets.info(:tower_db_events_cache) do
  :undefined -> :ets.new(:tower_db_events_cache, [:set, :named_table, :public, read_concurrency: true])
  _ -> :ok
end

ExUnit.start()

Ecto.Adapters.SQL.Sandbox.mode(TowerDB.TestRepo, :manual)
