defmodule TowerDB.MigrationPartialUpgradeTest do
  use ExUnit.Case, async: true

  alias Ecto.Adapters.SQL
  alias TowerDB.PartialUpgradeTestRepo, as: Repo
  alias TowerDB.PartialUpgradeTestRepo.Migrations.AddTowerDB
  alias TowerDB.PartialUpgradeTestRepo.Migrations.UpgradeTowerDB

  describe "up/1 and down/1 with :from and :to" do
    setup do
      Ecto.Adapters.SQL.Sandbox.mode(Repo, :auto)
      on_exit(fn -> Ecto.Adapters.SQL.Sandbox.mode(Repo, :manual) end)
      :ok
    end

    test "applies and reverts only the migrations between :from and :to" do
      refute table_exists?("tower_db_events")

      run_migration(:up, {1, AddTowerDB})
      assert table_exists?("tower_db_events")
      assert "similarity_id" in get_columns("tower_db_events")
      refute "normalized_reason" in get_columns("tower_db_events")

      run_migration(:up, {2, UpgradeTowerDB})
      assert "normalized_reason" in get_columns("tower_db_events")

      run_migration(:down, {2, UpgradeTowerDB})
      refute "normalized_reason" in get_columns("tower_db_events")
      assert "similarity_id" in get_columns("tower_db_events")

      run_migration(:down, {1, AddTowerDB})
      refute table_exists?("tower_db_events")
    end
  end

  defp run_migration(direction, migration) do
    Ecto.Migrator.run(Repo, [migration], direction, all: true)
  end

  defp table_exists?(table_name) do
    query = """
    SELECT EXISTS (
      SELECT FROM information_schema.tables
      WHERE table_schema = 'public'
      AND table_name = $1
    )
    """

    %{rows: [[exists]]} = SQL.query!(Repo, query, [table_name])
    exists
  end

  defp get_columns(table_name) do
    query = """
    SELECT column_name
    FROM information_schema.columns
    WHERE table_schema = 'public'
    AND table_name = $1
    """

    %{rows: rows} = SQL.query!(Repo, query, [table_name])
    List.flatten(rows)
  end
end
