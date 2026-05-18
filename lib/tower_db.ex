defmodule TowerDB do
  @moduledoc """
  A Tower reporter that persists events to a PostgreSQL database.

  ## Example

      config :tower, :reporters, [TowerDB]
  """

  @behaviour Tower.Reporter

  @impl true
  defdelegate report_event(event), to: TowerDB.Reporter
end
