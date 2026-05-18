defmodule TowerDB.MigrationTest do
  use ExUnit.Case, async: false

  import TowerDB.TestHelpers

  alias Ecto.Adapters.SQL

  describe "up/0" do
    setup do
      Ecto.Adapters.SQL.Sandbox.mode(TowerDB.TestRepo, :auto)
      on_exit(fn -> Ecto.Adapters.SQL.Sandbox.mode(TowerDB.TestRepo, :manual) end)
      :ok
    end

    test "creates tower_db_events table with indexes" do
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

      assert index_exists?("tower_db_events", "tower_db_events_datetime_index")
      assert index_exists?("tower_db_events", "tower_db_events_level_index")
    end
  end

  # Tests that run migrations use :auto mode since Ecto.Migrator
  # spawns a Task that needs automatic access to connections
  describe "down/0" do
    setup do
      Ecto.Adapters.SQL.Sandbox.mode(TowerDB.TestRepo, :auto)
      run_migration(:up)

      on_exit(fn ->
        run_migration(:up)
        Ecto.Adapters.SQL.Sandbox.mode(TowerDB.TestRepo, :manual)
      end)

      :ok
    end

    test "drops tower_db_events table and indexes" do
      assert table_exists?("tower_db_events")

      run_migration(:down)

      refute table_exists?("tower_db_events")
      refute index_exists?("tower_db_events", "tower_db_events_datetime_index")
      refute index_exists?("tower_db_events", "tower_db_events_level_index")
    end
  end

  describe "up/0 after down/0" do
    setup do
      Ecto.Adapters.SQL.Sandbox.mode(TowerDB.TestRepo, :auto)
      run_migration(:up)

      on_exit(fn ->
        run_migration(:up)
        Ecto.Adapters.SQL.Sandbox.mode(TowerDB.TestRepo, :manual)
      end)

      :ok
    end

    test "recreates table and indexes after rollback" do
      run_migration(:down)
      refute table_exists?("tower_db_events")

      run_migration(:up)

      assert table_exists?("tower_db_events")
      assert index_exists?("tower_db_events", "tower_db_events_datetime_index")
      assert index_exists?("tower_db_events", "tower_db_events_level_index")
    end
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
