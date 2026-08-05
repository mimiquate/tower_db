defmodule TowerDB.Migration do
  @moduledoc """
  Migration module for TowerDB.

  ## Usage

  To use migrations in your application you'll need to generate an `Ecto.Migration` that wraps
  calls to `TowerDB.Migration`:

      mix ecto.gen.migration add_tower_db

  Open the generated migration in your editor and call the `up` and `down` functions on
  `TowerDB.Migration`:

      defmodule MyApp.Repo.Migrations.AddTowerDB do
        use Ecto.Migration

        def up, do: TowerDB.Migration.up()
        def down, do: TowerDB.Migration.down()
      end
  """

  use Ecto.Migration

  @spec up() :: :ok
  def up do
    TowerDB.Migration.V01.up()
    TowerDB.Migration.V02.up()
    TowerDB.Migration.V03.up()
    TowerDB.Migration.V04.up()
  end

  @spec down() :: :ok
  def down do
    TowerDB.Migration.V04.down()
    TowerDB.Migration.V03.down()
    TowerDB.Migration.V02.down()
    TowerDB.Migration.V01.down()
  end
end
