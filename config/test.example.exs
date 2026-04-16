import Config

config :tower_db,
  repo: TowerDB.TestRepo,
  ecto_repos: [TowerDB.TestRepo]

config :tower_db, TowerDB.TestRepo,
  username: "postgres",
  password: "postgres",
  database: "tower_db_test",
  hostname: "localhost",
  pool: Ecto.Adapters.SQL.Sandbox,
  priv: "priv/test_repo"
