defmodule TowerDB.Repo do
  @moduledoc false

  def repo do
    Application.fetch_env!(:tower_db, :repo)
  end
end
