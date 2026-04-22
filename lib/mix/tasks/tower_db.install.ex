if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.TowerDb.Install do
    @shortdoc "Installs TowerDB. Invoke with `mix igniter.install tower_db`"
    @moduledoc """
    #{@shortdoc}

    ## Example

    ```bash
    mix igniter.install tower_db
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
        adds_deps: [],
        installs: [],
        example: "mix tower_db.install",
        only: nil,
        positional: [],
        composes: [],
        schema: [repo: :string],
        defaults: [],
        aliases: [r: :repo],
        required: []
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
          |> Igniter.Project.Config.configure_new("config.exs", app_name, [:repo], repo)
          |> then(fn igniter ->
            if Code.ensure_loaded?(Tower.Igniter) do
              Tower.Igniter.reporters_list_append(igniter, TowerDB)
            else
              igniter
            end
          end)
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
          {:ok, repo, extract_adapter(igniter, repo)}

        {false, igniter} ->
          {:error, Igniter.add_issue(igniter, "Provided repo (#{inspect(repo)}) doesn't exist")}
      end
    end

    defp find_supported_repo(igniter, app_name, repos) do
      with_adapters = Enum.map(repos, &{&1, extract_adapter(igniter, &1)})

      case Enum.find(with_adapters, fn {_, adapter} -> adapter in @supported_adapters end) do
        {repo, adapter} ->
          {:ok, repo, adapter}

        nil ->
          unsupported_list =
            Enum.map_join(with_adapters, "\n", fn {repo, adapter} ->
              "  * #{inspect(repo)} (#{inspect(adapter)})"
            end)

          issue = """
          No compatible Ecto repo found for #{inspect(app_name)}.

          TowerDB requires PostgreSQL. Found repos with unsupported adapters:
          #{unsupported_list}

          Specify a compatible repo explicitly with: mix tower_db.install --repo MyApp.Repo
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
    @shortdoc "Installs TowerDB. Invoke with `mix igniter.install tower_db`"

    @moduledoc """
    #{@shortdoc}

    ## Example

    ```bash
    mix igniter.install tower_db
    ```
    """

    use Mix.Task

    @impl Mix.Task
    def run(_argv) do
      Mix.shell().error("""
      The task 'tower_db.install' requires igniter. Please install igniter and try again.

      For more information, see: https://hexdocs.pm/igniter/readme.html#installation
      """)

      exit({:shutdown, 1})
    end
  end
end
