defmodule TowerDB.Migration.SQLMigrator do
  @moduledoc false

  use Ecto.Migration

  import Ecto.Query

  alias Ecto.Adapters.SQL

  def migrate_up(migrator, opts, initial_version) do
    initial = migrated_version(opts)

    cond do
      initial == 0 ->
        change(migrator, initial_version..opts.version, :up, opts)

      initial < opts.version ->
        change(migrator, (initial + 1)..opts.version, :up, opts)

      true ->
        :ok
    end
  end

  def migrate_down(migrator, opts, initial_version) do
    initial = max(migrated_version(opts), initial_version)

    if initial >= opts.version do
      change(migrator, initial..opts.version//-1, :down, opts)
    else
      :ok
    end
  end

  def migrated_version(opts) do
    repo = Map.get_lazy(opts, :repo, fn -> TowerDB.Repo.repo() end)

    query =
      from meta in "tower_db_meta",
        where: meta.key == "migrated_version",
        select: meta.value

    with true <- meta_table_exists?(repo),
         version when is_binary(version) <- repo.one(query, log: false) do
      String.to_integer(version)
    else
      _other -> 0
    end
  end

  defp change(migrator, versions_range, direction, opts) do
    for version <- versions_range do
      padded_version = String.pad_leading(to_string(version), 2, "0")

      migration_module = Module.concat(migrator, "V#{padded_version}")
      apply(migration_module, direction, [opts])
    end

    case direction do
      :up -> record_version(opts, Enum.max(versions_range))
      :down -> record_version(opts, Enum.min(versions_range) - 1)
    end
  end

  defp record_version(_opts, 0), do: :ok

  defp record_version(_opts, version) do
    execute("""
    INSERT INTO tower_db_meta (key, value, inserted_at, updated_at)
    VALUES ('migrated_version', '#{version}', NOW(), NOW())
    ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = NOW()
    """)
  end

  defp meta_table_exists?(repo) do
    repo
    |> SQL.query!(
      "SELECT TRUE FROM information_schema.tables WHERE table_name = 'tower_db_meta' AND table_schema = 'public'",
      [],
      log: false
    )
    |> Map.get(:rows)
    |> Enum.any?()
  end
end
