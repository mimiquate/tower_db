defmodule TowerDB do
  @moduledoc """
  A Tower reporter that persists events to a PostgreSQL database.

  ## Example

      config :tower, :reporters, [TowerDB]
  """

  @behaviour Tower.Reporter

  @impl true
  defdelegate report_event(event), to: TowerDB.Reporter

  postgrex_json_library = Application.compile_env(:postgrex, :json_library)

  cond do
    postgrex_json_library == Jason && not Code.ensure_loaded?(Jason) ->
      raise """
      TowerDB uses map columns, postgrex uses Jason by default.
        Include the jason package in your dependencies, or configure one explicitly
        config :postgrex, :json_library, JSON
        Elixir's built-in JSON on Elixir 1.18+
      """

    true ->
      :ok
  end

  def enable do
    Application.put_env(:tower_db, :enabled, true)
  end

  def disable do
    Application.put_env(:tower_db, :enabled, false)
  end
end
