import Config

config :tower_db, TowerDB.TestRepo,
  pool: Ecto.Adapters.SQL.Sandbox,
  priv: "priv/test_repo",
  url: System.get_env("POSTGRES_URL") || "postgres://localhost:5432/tower_db_test",
  log: false

config :tower_db,
  repo: TowerDB.TestRepo,
  ecto_repos: [TowerDB.TestRepo]
