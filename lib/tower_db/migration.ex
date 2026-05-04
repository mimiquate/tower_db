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

  import Ecto.Query

  alias Ecto.Adapters.SQL

  @initial_version 1
  @current_version 1

  @spec up(Keyword.t()) :: :ok
  def up(opts \\ []) do
    opts = with_defaults(opts, @current_version)
    migrate_up(opts)
  end

  @spec down(Keyword.t()) :: :ok
  def down(opts \\ []) do
    opts = with_defaults(opts, @initial_version)
    migrate_down(opts)
  end

  @spec migrated_version(Keyword.t()) :: non_neg_integer()
  def migrated_version(opts \\ []) do
    opts = with_defaults(opts, @initial_version)
    get_migrated_version(opts)
  end

  defp with_defaults(opts, default_version) do
    opts = Enum.into(opts, %{version: default_version})
    validate_version!(opts.version)
    opts
  end

  defp validate_version!(version) do
    unless is_integer(version) and version in @initial_version..@current_version do
      raise ArgumentError,
            "invalid version #{inspect(version)}. " <>
              "Version must be an integer between #{@initial_version} and #{@current_version}."
    end
  end

  defp migrate_up(opts) do
    initial = get_migrated_version(opts)

    cond do
      initial == 0 ->
        change(@initial_version..opts.version, :up, opts)

      initial < opts.version ->
        change((initial + 1)..opts.version, :up, opts)

      true ->
        :ok
    end
  end

  defp migrate_down(opts) do
    initial = max(get_migrated_version(opts), @initial_version)

    if initial >= opts.version do
      change(initial..opts.version//-1, :down, opts)
    else
      :ok
    end
  end

  defp get_migrated_version(opts) do
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

  defp change(versions_range, direction, opts) do
    for version <- versions_range do
      padded_version = String.pad_leading(to_string(version), 2, "0")

      migration_module = Module.concat(__MODULE__, "V#{padded_version}")
      apply(migration_module, direction, [opts])
    end

    case direction do
      :up -> record_version(Enum.max(versions_range))
      :down -> record_version(Enum.min(versions_range) - 1)
    end
  end

  defp record_version(0), do: :ok

  defp record_version(version) do
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
