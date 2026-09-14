defmodule TowerDB.Reporter do
  @moduledoc """
  Tower reporter that stores events in a database.
  """
  require Logger

  @behaviour Tower.Reporter

  @impl true
  def report_event(%Tower.Event{} = event) do
    do_report_event(event)
  end

  defp do_report_event(%Tower.Event{} = event) do
    attrs = %{
      id: event.id,
      similarity_id: event.similarity_id,
      datetime: event.datetime,
      level: event.level,
      kind: event.kind,
      reason: event.reason,
      stacktrace: event.stacktrace,
      metadata: event.metadata,
      request_data: request_data(event.plug_conn)
    }

    case TowerDB.Events.create_event(attrs) do
      {:error, reason} ->
        Logger.error("[TowerDB] Error creating event in DB: #{inspect(reason)}")

      {:ok, _event} ->
        nil
    end
  end

  defp request_data(%Plug.Conn{} = conn), do: TowerDB.RequestData.build(conn)
  defp request_data(_), do: nil
end
