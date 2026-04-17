defmodule TowerDB.Migration.Postgres do
  @moduledoc false

  @behaviour TowerDB.Migration

  use Ecto.Migration

  alias TowerDB.Migration.SQLMigrator

  @initial_version 1
  @current_version 3
  @default_prefix "public"

  @impl TowerDB.Migration
  def up(opts) do
    opts = with_defaults(opts, @current_version)
    SQLMigrator.migrate_up(__MODULE__, opts, @initial_version)
  end

  @impl TowerDB.Migration
  def down(opts) do
    opts = with_defaults(opts, @initial_version)
    SQLMigrator.migrate_down(__MODULE__, opts, @initial_version)
  end

  @impl TowerDB.Migration
  def migrated_version(opts) do
    opts = with_defaults(opts, @initial_version)
    SQLMigrator.migrated_version(opts)
  end

  defp with_defaults(opts, version) do
    opts = Enum.into(opts, %{prefix: @default_prefix, version: version})

    opts
    |> Map.put_new(:create_schema, opts.prefix != @default_prefix)
  end
end
