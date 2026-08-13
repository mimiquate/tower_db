defmodule TowerDB.PartialUpgradeTestRepo do
  use Ecto.Repo,
    otp_app: :tower_db,
    adapter: Ecto.Adapters.Postgres
end
