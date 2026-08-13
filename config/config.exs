import Config

config :tower_db, TowerDB.TestRepo,
  pool: Ecto.Adapters.SQL.Sandbox,
  priv: "test/support/test_repo",
  url: System.get_env("POSTGRES_URL") || "postgres://localhost:5432/tower_db_test",
  log: false

config :tower_db, TowerDB.PartialUpgradeTestRepo,
  pool: Ecto.Adapters.SQL.Sandbox,
  priv: "test/support/partial_upgrade_test_repo",
  url:
    System.get_env("PARTIAL_UPGRADE_POSTGRES_URL") ||
      "postgres://localhost:5432/tower_db_test_partial_upgrade",
  log: false

config :tower_db,
  repo: TowerDB.TestRepo,
  ecto_repos: [TowerDB.TestRepo, TowerDB.PartialUpgradeTestRepo]

config :logger, level: :warning
