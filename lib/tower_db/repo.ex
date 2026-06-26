defmodule TowerDB.Repo do
  @moduledoc false

  def repo do
    Application.fetch_env!(:tower_db, :repo)
  end

  def max_events do
    Application.get_env(:tower_db, :max_events)
  end

  def cleanup_strategy do
    Application.get_env(:tower_db, :cleanup_strategy)
  end
end
