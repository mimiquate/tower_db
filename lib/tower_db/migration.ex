defmodule TowerDB.Migration do
  @moduledoc """
  Migration module for TowerDB.

  This module delegates to adapter-specific implementations based on the
  configured Ecto adapter.

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

  @callback up(Keyword.t()) :: :ok
  @callback down(Keyword.t()) :: :ok
  @callback migrated_version(Keyword.t()) :: non_neg_integer()

  @spec up(Keyword.t()) :: :ok
  def up(opts \\ []) when is_list(opts) do
    migrator().up(opts)
  end

  @spec down(Keyword.t()) :: :ok
  def down(opts \\ []) when is_list(opts) do
    migrator().down(opts)
  end

  @spec migrated_version(Keyword.t()) :: non_neg_integer()
  def migrated_version(opts \\ []) when is_list(opts) do
    migrator().migrated_version(opts)
  end

  defp migrator do
    case TowerDB.Repo.repo().__adapter__() do
      Ecto.Adapters.Postgres -> TowerDB.Migration.Postgres
      adapter -> raise "TowerDB does not support #{inspect(adapter)}"
    end
  end
end
