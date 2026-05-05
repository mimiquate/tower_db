defmodule TowerDB.MigrationTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL

  describe "up/0" do
    setup do
      :ok = Ecto.Adapters.SQL.Sandbox.checkout(TowerDB.TestRepo)
      Ecto.Adapters.SQL.Sandbox.mode(TowerDB.TestRepo, {:shared, self()})
      :ok
    end

    test "creates tower_db_meta table" do
      assert table_exists?("tower_db_meta")

      columns = get_columns("tower_db_meta")

      assert "key" in columns
      assert "value" in columns
      assert "inserted_at" in columns
      assert "updated_at" in columns
    end

    test "creates tower_db_events table" do
      assert table_exists?("tower_db_events")

      columns = get_columns("tower_db_events")

      assert "id" in columns
      assert "datetime" in columns
      assert "level" in columns
      assert "reason" in columns
      assert "stacktrace" in columns
      assert "metadata" in columns
      assert "inserted_at" in columns
      assert "updated_at" in columns
    end

    test "creates indexes on tower_db_events" do
      assert index_exists?("tower_db_events", "tower_db_events_datetime_index")
      assert index_exists?("tower_db_events", "tower_db_events_level_index")
    end
  end

  # Tests that run migrations need to avoid sandbox since Ecto.Migrator
  # spawns a Task that can't share sandbox connections
  describe "down/0" do
    setup do
      run_migration(:up)
      on_exit(fn -> run_migration(:up) end)
      :ok
    end

    test "drops tower_db_events table" do
      assert table_exists?("tower_db_events")

      run_migration(:down)

      refute table_exists?("tower_db_events")
    end

    test "drops tower_db_meta table" do
      assert table_exists?("tower_db_meta")

      run_migration(:down)

      refute table_exists?("tower_db_meta")
    end

    test "drops indexes" do
      assert index_exists?("tower_db_events", "tower_db_events_datetime_index")

      run_migration(:down)

      refute index_exists?("tower_db_events", "tower_db_events_datetime_index")
      refute index_exists?("tower_db_events", "tower_db_events_level_index")
    end
  end

  describe "up/0 after down/0" do
    setup do
      run_migration(:up)
      :ok
    end

    test "recreates tables after rollback" do
      run_migration(:down)
      refute table_exists?("tower_db_events")
      refute table_exists?("tower_db_meta")

      run_migration(:up)

      assert table_exists?("tower_db_events")
      assert table_exists?("tower_db_meta")
    end

    test "recreates indexes after rollback" do
      run_migration(:down)

      run_migration(:up)

      assert index_exists?("tower_db_events", "tower_db_events_datetime_index")
      assert index_exists?("tower_db_events", "tower_db_events_level_index")
    end
  end

  describe "migrated_version/0" do
    setup do
      run_migration(:up)
      on_exit(fn -> run_migration(:up) end)
      :ok
    end

    test "returns current migration version" do
      assert TowerDB.Migration.migrated_version(repo: TowerDB.TestRepo) == 1
    end

    test "returns 0 when no migrations have run" do
      run_migration(:down)

      assert TowerDB.Migration.migrated_version(repo: TowerDB.TestRepo) == 0
    end
  end

  describe "version validation" do
    setup do
      :ok = Ecto.Adapters.SQL.Sandbox.checkout(TowerDB.TestRepo)
      Ecto.Adapters.SQL.Sandbox.mode(TowerDB.TestRepo, {:shared, self()})
      :ok
    end

    test "raises error for version above current" do
      assert_raise ArgumentError, ~r/invalid version/, fn ->
        TowerDB.Migration.up(version: 999)
      end
    end

    test "raises error for version below initial" do
      assert_raise ArgumentError, ~r/invalid version/, fn ->
        TowerDB.Migration.up(version: 0)
      end
    end

    test "raises error for non-integer version" do
      assert_raise ArgumentError, ~r/invalid version/, fn ->
        TowerDB.Migration.up(version: "1")
      end
    end
  end

  defp run_migration(direction) do
    Ecto.Migrator.run(
      TowerDB.TestRepo,
      [{0, TowerDB.TestRepo.Migrations.CreateEvents}],
      direction,
      all: true
    )
  end

  defp table_exists?(table_name) do
    query = """
    SELECT EXISTS (
      SELECT FROM information_schema.tables
      WHERE table_schema = 'public'
      AND table_name = $1
    )
    """

    %{rows: [[exists]]} = SQL.query!(TowerDB.TestRepo, query, [table_name])
    exists
  end

  defp index_exists?(table_name, index_name) do
    query = """
    SELECT EXISTS (
      SELECT FROM pg_indexes
      WHERE schemaname = 'public'
      AND tablename = $1
      AND indexname = $2
    )
    """

    %{rows: [[exists]]} = SQL.query!(TowerDB.TestRepo, query, [table_name, index_name])
    exists
  end

  defp get_columns(table_name) do
    query = """
    SELECT column_name
    FROM information_schema.columns
    WHERE table_schema = 'public'
    AND table_name = $1
    """

    %{rows: rows} = SQL.query!(TowerDB.TestRepo, query, [table_name])
    List.flatten(rows)
  end
end
