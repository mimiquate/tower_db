defmodule TowerDBTest do
  use ExUnit.Case
  doctest TowerDB

  import ExUnit.CaptureLog, only: [capture_log: 1]

  setup do
    put_env(:tower, :reporters, [TowerDB])

    :ok
  end

  test "logs database error message when inserting" do
    assert capture_log(fn ->
             assert :ok = Tower.report_message(:invalid_level, "message")
           end) =~ ~r/\[TowerDB\] Error creating event in DB: #Ecto.Changeset/
  end

  describe "enable/0 and disable/0" do
    setup do
      original_value = Application.get_env(:tower_db, :enabled)

      on_exit(fn ->
        if original_value == nil do
          Application.delete_env(:tower_db, :enabled)
        else
          Application.put_env(:tower_db, :enabled, original_value)
        end
      end)

      :ok
    end

    test "disable/0 sets the :enabled config to false" do
      TowerDB.disable()

      assert Application.get_env(:tower_db, :enabled) == false
    end

    test "enable/0 sets the :enabled config to true" do
      TowerDB.disable()
      TowerDB.enable()

      assert Application.get_env(:tower_db, :enabled) == true
    end
  end

  defp put_env(app, key, value) do
    original_value = Application.get_env(app, key)
    Application.put_env(app, key, value)

    on_exit(fn ->
      if original_value == nil do
        Application.delete_env(app, key)
      else
        Application.put_env(app, key, original_value)
      end
    end)
  end
end
