defmodule TowerDBTest do
  use ExUnit.Case
  doctest TowerDB

  test "greets the world" do
    assert TowerDB.hello() == :world
  end
end
