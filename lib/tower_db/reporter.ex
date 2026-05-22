defmodule TowerDB.Reporter do
  @moduledoc """
  Tower reporter that stores events in a database.
  """
  require Logger

  @behaviour Tower.Reporter

  @default_level :error

  @impl true
  def report_event(%Tower.Event{level: level} = event) do
    if Tower.equal_or_greater_level?(level, @default_level) do
      do_report_event(event)
    end

    :ok
  end

  defp do_report_event(%Tower.Event{} = event) do
    attrs = %{
      similarity_id: event.similarity_id,
      datetime: event.datetime,
      level: event.level,
      kind: event.kind,
      reason: event.reason,
      stacktrace: event.stacktrace,
      log_event: event.log_event,
      plug_conn: event.plug_conn,
      metadata: event.metadata,
      by: if(event.by, do: inspect(event.by))
    }

    case TowerDB.Events.create_event(attrs) do
      {:ok, event} -> Logger.info("Event id: #{event.id} was inserted")
      {:error, reason} -> Logger.error("[TowerDB] Insert failed: #{inspect(reason)}")
    end
  end
end
