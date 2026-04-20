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

  defp with_defaults(opts, default_version) do
    opts = Enum.into(opts, %{prefix: @default_prefix, version: default_version})
    validate_prefix!(opts.prefix)
    validate_version!(opts.version)

    opts
    |> Map.put_new(:create_schema, opts.prefix != @default_prefix)
  end

  defp validate_version!(version) do
    unless is_integer(version) and version in @initial_version..@current_version do
      raise ArgumentError,
            "invalid version #{inspect(version)}. " <>
              "Version must be an integer between #{@initial_version} and #{@current_version}."
    end
  end

  defp validate_prefix!(prefix) do
    unless valid_identifier?(prefix) do
      raise ArgumentError,
            "invalid prefix #{inspect(prefix)}. " <>
              "Prefix must start with a letter or underscore, " <>
              "contain only letters, digits, and underscores, " <>
              "and be between 1 and 63 characters."
    end
  end

  defp valid_identifier?(prefix) when is_binary(prefix) do
    byte_size(prefix) in 1..63 and prefix =~ ~r/^[a-zA-Z_][a-zA-Z0-9_]*$/
  end

  defp valid_identifier?(_), do: false
end
