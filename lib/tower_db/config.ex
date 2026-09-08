defmodule TowerDB.Config do
  @moduledoc false

  def enabled? do
    Application.get_env(:tower_db, :enabled, true)
  end
end
