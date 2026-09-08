defmodule TowerDB.Reporter do
  @moduledoc """
  Tower reporter that stores events in a database.
  """
  require Logger

  @behaviour Tower.Reporter

  @impl true
  def report_event(%Tower.Event{} = event) do
    if TowerDB.Config.enabled?() do
      do_report_event(event)
    else
      Logger.debug("[TowerDB] Reporter disabled, ignoring event")
      :ok
    end
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
      metadata: event.metadata
    }

    case TowerDB.Events.create_event(attrs) do
      {:error, reason} ->
        Logger.error("[TowerDB] Error creating event in DB: #{inspect(reason)}")

      {:ok, _event} ->
        nil
    end
  end
end
