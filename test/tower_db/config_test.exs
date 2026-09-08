defmodule TowerDB.ConfigTest do
  use ExUnit.Case, async: false

  alias TowerDB.Config

  describe "enabled?/0" do
    test "defaults to true when not configured" do
      put_env(:tower_db, :enabled, nil)

      assert Config.enabled?() == true
    end

    test "returns the configured value" do
      put_env(:tower_db, :enabled, false)

      assert Config.enabled?() == false
    end
  end

  defp put_env(app, key, value) do
    original_value = Application.get_env(app, key)

    if value == nil do
      Application.delete_env(app, key)
    else
      Application.put_env(app, key, value)
    end

    on_exit(fn ->
      if original_value == nil do
        Application.delete_env(app, key)
      else
        Application.put_env(app, key, original_value)
      end
    end)
  end
end
