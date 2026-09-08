defmodule TowerDB do
  @moduledoc """
  A Tower reporter that persists events to a PostgreSQL database.

  ## Example

      config :tower, :reporters, [TowerDB]
  """

  @behaviour Tower.Reporter

  @impl true
  defdelegate report_event(event), to: TowerDB.Reporter

  @doc """
  Enables the TowerDB reporter, so future events are persisted.

  Can be called from a remote shell to re-enable the reporter at runtime.
  """
  def enable do
    Application.put_env(:tower_db, :enabled, true)
  end

  @doc """
  Disables the TowerDB reporter, so future events are ignored.

  Can be called from a remote shell to disable the reporter at runtime,
  for example during an incident.
  """
  def disable do
    Application.put_env(:tower_db, :enabled, false)
  end
end
