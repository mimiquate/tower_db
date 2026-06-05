defmodule TowerDB.Reporter do
  @moduledoc """
  Tower reporter that stores events in a database.

  Uses a circuit breaker pattern to handle database failures gracefully.
  When the database is unavailable, events are queued and retried once
  the connection recovers.
  """
  require Logger

  alias TowerDB.CircuitBreaker

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

    case CircuitBreaker.call(attrs, fn -> TowerDB.Events.create_event(attrs) end) do
      {:ok, event} ->
        Logger.info("Event id: #{event.id} was inserted")

      {:queued, :circuit_open} ->
        Logger.warning("[TowerDB] Event queued - circuit breaker open")

      {:dropped, :queue_full} ->
        Logger.error("[TowerDB] Event dropped - queue full")

      {:error, reason} ->
        Logger.error("[TowerDB] Insert failed: #{inspect(reason)}")
    end
  end
end
