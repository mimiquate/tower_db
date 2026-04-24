defmodule TowerDB.Reporter do
  @moduledoc """
  Tower reporter that stores events in a database.
  """

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
      datetime: event.datetime,
      level: event.level,
      reason: event.reason,
      stacktrace: event.stacktrace,
      metadata: event.metadata
    }

    TowerDB.Events.create_event(attrs)
  end
end
