defmodule TowerDB do
  @moduledoc """
  A Tower reporter that persists events to a PostgreSQL database.

  ## Example

      config :tower, :reporters, [TowerDB]
  """

  @behaviour Tower.Reporter

  @impl true
  defdelegate report_event(event), to: TowerDB.Reporter

  configured_json_library = Application.compile_env(:postgrex, :json_library)

  cond do
    configured_json_library && Code.ensure_loaded?(configured_json_library) ->
      def json_module, do: unquote(configured_json_library)

    is_nil(configured_json_library) && Code.ensure_loaded?(Jason) ->
      def json_module, do: Jason

    true ->
      raise "Postgrex needs a JSON library to persist tower_db's jsonb columns. " <>
              "Include the jason package in your dependencies, or configure one explicitly " <>
              "(for example, Elixir's built-in JSON on Elixir 1.18+) with " <>
              "`config :postgrex, :json_library, YourLibraryOfChoice`"
  end
end
