defmodule TowerDB.Reporter do
  @moduledoc """
  Tower reporter that stores events in a database.

  Events are buffered and flushed in batches to improve throughput.
  Uses a circuit breaker pattern to handle database failures gracefully.
  When the database is unavailable, batches are queued and retried once
  the connection recovers.
  """

  alias TowerDB.Buffer

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

    Buffer.add(attrs)
  end
end
