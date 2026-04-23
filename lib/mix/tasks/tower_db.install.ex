if Code.ensure_loaded?(Igniter) and
     Code.ensure_loaded?(Tower.Igniter) and
     function_exported?(Tower.Igniter, :reporters_list_append, 2) do
  defmodule Mix.Tasks.TowerDb.Install do
    @example "mix igniter.install tower_db"

    @shortdoc "Installs TowerDB. Invoke with `#{@example}`"
    @moduledoc """
    #{@shortdoc}

    ## Example

    ```bash
    #{@example}
    ```

    ## Options

    * `--repo` or `-r` — Specify an Ecto repo for TowerDB to use
    """

    use Igniter.Mix.Task

    @supported_adapters [Ecto.Adapters.Postgres]

    @impl Igniter.Mix.Task
    def info(_argv, _composing_task) do
      %Igniter.Mix.Task.Info{
        group: :tower,
        example: @example,
        schema: [repo: :string],
        aliases: [r: :repo]
      }
    end

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      app_name = Igniter.Project.Application.app_name(igniter)
      opts = igniter.args.options

      case extract_repo(igniter, app_name, opts[:repo]) do
        {:ok, repo, _adapter} ->
          migration = """
          def up, do: TowerDB.Migration.up()
          def down, do: TowerDB.Migration.down(version: 1)
          """

          igniter
          |> Igniter.Project.Config.configure_new("config.exs", :tower_db, [:repo], repo)
          |> Tower.Igniter.reporters_list_append(TowerDB)
          |> Igniter.Project.Formatter.import_dep(:tower_db)
          |> Igniter.Libs.Ecto.gen_migration(repo, "add_tower_db",
            body: migration,
            on_exists: :skip
          )

        {:error, igniter} ->
          igniter
      end
    end

    defp extract_repo(igniter, app_name, nil) do
      case Igniter.Libs.Ecto.list_repos(igniter) do
        {igniter, repos} when repos != [] ->
          find_supported_repo(igniter, app_name, repos)

        _ ->
          issue = """
          No Ecto repos found for #{inspect(app_name)}.

          Ensure `:ecto` is installed and configured for the current application.
          """

          {:error, Igniter.add_issue(igniter, issue)}
      end
    end

    defp extract_repo(igniter, _app_name, module) do
      repo = Igniter.Project.Module.parse(module)

      case Igniter.Project.Module.module_exists(igniter, repo) do
        {true, igniter} ->
          adapter = extract_adapter(igniter, repo)

          if adapter in @supported_adapters do
            {:ok, repo, adapter}
          else
            issue = """
            Provided repo (#{inspect(repo)}) uses #{inspect(adapter)}.

            TowerDB only supports PostgreSQL (Ecto.Adapters.Postgres).
            """

            {:error, Igniter.add_issue(igniter, issue)}
          end

        {false, igniter} ->
          {:error, Igniter.add_issue(igniter, "Provided repo (#{inspect(repo)}) doesn't exist")}
      end
    end

    defp find_supported_repo(igniter, app_name, repos) do
      repos
      |> Enum.map(&{&1, extract_adapter(igniter, &1)})
      |> Enum.filter(fn {_, adapter} -> adapter in @supported_adapters end)
      |> case do
        [{repo, adapter}] ->
          {:ok, repo, adapter}

        [] ->
          issue = """
          No compatible Ecto repo found for #{inspect(app_name)}.

          TowerDB requires PostgreSQL (Ecto.Adapters.Postgres).
          """

          {:error, Igniter.add_issue(igniter, issue)}

        multiple ->
          repo_list =
            Enum.map_join(multiple, "\n", fn {repo, _} ->
              "  * #{inspect(repo)}"
            end)

          issue = """
          Multiple compatible Ecto repos found for #{inspect(app_name)}:
          #{repo_list}

          Please specify which repo to use: mix tower_db.install --repo MyApp.Repo
          """

          {:error, Igniter.add_issue(igniter, issue)}
      end
    end

    defp extract_adapter(igniter, repo) do
      with {:ok, {_, _, zipper}} <- Igniter.Project.Module.find_module(igniter, repo),
           {:ok, zipper} <- Igniter.Code.Module.move_to_use(zipper, Ecto.Repo),
           {:ok, zipper} <- Igniter.Code.Function.move_to_nth_argument(zipper, 1),
           {:ok, zipper} <- Igniter.Code.Keyword.get_key(zipper, :adapter),
           {:ok, adapter} <- Igniter.Code.Common.expand_literal(zipper) do
        adapter
      else
        _ -> Ecto.Adapters.Postgres
      end
    end
  end
else
  defmodule Mix.Tasks.TowerDb.Install do
    @example "mix igniter.install tower_db"

    @shortdoc "Installs TowerDB. Invoke with `#{@example}`"

    @moduledoc """
    #{@shortdoc}

    ## Example

    ```bash
    #{@example}
    ```
    """

    use Mix.Task

    @impl Mix.Task
    def run(_argv) do
      Mix.shell().error("""
      The task 'tower_db.install' requires igniter and tower >= 0.8.

      Please verify that those conditions are met in your project.

      For more information, see: https://hexdocs.pm/igniter/readme.html#installation
      """)

      exit({:shutdown, 1})
    end
  end
end
