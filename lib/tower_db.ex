defmodule TowerDB do
  @moduledoc """
  A Tower reporter that persists events to a PostgreSQL database.

  ## Example

      config :tower, :reporters, [TowerDB]
  """

  @behaviour Tower.Reporter

  @impl true
  defdelegate report_event(event), to: TowerDB.Reporter

  def enable do
    Application.put_env(:tower_db, :enabled, true)
  end

  def disable do
    Application.put_env(:tower_db, :enabled, false)
  end
end
