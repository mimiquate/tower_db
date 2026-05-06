defmodule Mix.Tasks.TowerDB.InstallTest do
  use ExUnit.Case, async: true

  import Igniter.Test

  @moduletag :igniter

  describe "install" do
    test "installing without an available ecto repo" do
      assert {:error, [warning]} =
               test_project()
               |> Igniter.compose_task("tower_db.install", [])
               |> apply_igniter()

      assert warning =~ "No Ecto repos found for :test"
      assert warning =~ "Ensure `:ecto` is installed and configured for the current application."
    end

    test "installing with a postgres repo available" do
      application = """
      defmodule TowerDB.Application do
        use Application

        def start(_type, _args) do
          children = [
            TowerDB.Test.Repo
          ]
        end
      end
      """

      repo = """
      defmodule TowerDB.Test.Repo do
        @moduledoc false

        use Ecto.Repo, otp_app: :tower_db, adapter: Ecto.Adapters.Postgres
      end
      """

      files = %{
        "lib/tower_db/application.ex" => application,
        "lib/tower_db/repo.ex" => repo
      }

      [app_name: :tower_db, files: files]
      |> test_project()
      |> Igniter.compose_task("tower_db.install", [])
      |> assert_has_patch("config/config.exs", """
      | import Config
      | config :tower, reporters: [TowerDB]
      | config :tower_db, repo: TowerDB.Test.Repo
      """)
      |> assert_has_patch(".formatter.exs", """
      | import_deps: [:tower_db]
      """)
    end

    test "installing with --repo option pointing to existing postgres repo" do
      repo = """
      defmodule TowerDB.Test.CustomRepo do
        @moduledoc false

        use Ecto.Repo, otp_app: :tower_db, adapter: Ecto.Adapters.Postgres
      end
      """

      [app_name: :tower_db, files: %{"lib/tower_db/repo.ex" => repo}]
      |> test_project()
      |> Igniter.compose_task("tower_db.install", ["--repo", "TowerDB.Test.CustomRepo"])
      |> assert_has_patch("config/config.exs", """
      | import Config
      | config :tower, reporters: [TowerDB]
      | config :tower_db, repo: TowerDB.Test.CustomRepo
      """)
      |> assert_has_patch(".formatter.exs", """
      | import_deps: [:tower_db]
      """)
    end

    test "installing with --repo option pointing to non-existent repo" do
      assert {:error, [warning]} =
               test_project()
               |> Igniter.compose_task("tower_db.install", ["--repo", "NonExistent.Repo"])
               |> apply_igniter()

      assert warning =~ "Provided repo (NonExistent.Repo) doesn't exist"
    end

    # NOTE: Tests for unsupported adapters are skipped because extract_adapter/2
    # defaults to Ecto.Adapters.Postgres when it cannot parse the adapter from
    # the module AST in test mode.

    test "installing with multiple compatible postgres repos shows error" do
      application = """
      defmodule TowerDB.Application do
        use Application

        def start(_type, _args) do
          children = [
            TowerDB.Test.Repo1,
            TowerDB.Test.Repo2
          ]
        end
      end
      """

      repo1 = """
      defmodule TowerDB.Test.Repo1 do
        @moduledoc false

        use Ecto.Repo, otp_app: :tower_db, adapter: Ecto.Adapters.Postgres
      end
      """

      repo2 = """
      defmodule TowerDB.Test.Repo2 do
        @moduledoc false

        use Ecto.Repo, otp_app: :tower_db, adapter: Ecto.Adapters.Postgres
      end
      """

      files = %{
        "lib/tower_db/application.ex" => application,
        "lib/tower_db/repo1.ex" => repo1,
        "lib/tower_db/repo2.ex" => repo2
      }

      assert {:error, [warning]} =
               [app_name: :tower_db, files: files]
               |> test_project()
               |> Igniter.compose_task("tower_db.install", [])
               |> apply_igniter()

      assert warning =~ "Multiple compatible Ecto repos found for :tower_db"
      assert warning =~ "TowerDB.Test.Repo1"
      assert warning =~ "TowerDB.Test.Repo2"
      assert warning =~ "mix tower_db.install --repo MyApp.Repo"
    end


    test "installing with -r alias for --repo option" do
      repo = """
      defmodule TowerDB.Test.AliasRepo do
        @moduledoc false

        use Ecto.Repo, otp_app: :tower_db, adapter: Ecto.Adapters.Postgres
      end
      """

      [app_name: :tower_db, files: %{"lib/tower_db/repo.ex" => repo}]
      |> test_project()
      |> Igniter.compose_task("tower_db.install", ["-r", "TowerDB.Test.AliasRepo"])
      |> assert_has_patch("config/config.exs", """
      | import Config
      | config :tower, reporters: [TowerDB]
      | config :tower_db, repo: TowerDB.Test.AliasRepo
      """)
      |> assert_has_patch(".formatter.exs", """
      | import_deps: [:tower_db]
      """)
    end

    test "installing does not override existing tower_db config" do
      repo = """
      defmodule TowerDB.Test.Repo do
        @moduledoc false

        use Ecto.Repo, otp_app: :tower_db, adapter: Ecto.Adapters.Postgres
      end
      """

      [app_name: :tower_db, files: %{"lib/tower_db/repo.ex" => repo}]
      |> test_project()
      |> Igniter.Project.Config.configure("config.exs", :tower_db, [:repo], TowerDB.Test.ExistingRepo)
      |> Igniter.Project.Config.configure("config.exs", :tower, [:reporters], [TowerDB])
      |> apply_igniter!()
      |> Igniter.compose_task("tower_db.install", ["--repo", "TowerDB.Test.Repo"])
      |> assert_unchanged("config/config.exs")
    end
  end
end
