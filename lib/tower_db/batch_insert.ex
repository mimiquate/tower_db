defmodule TowerDB.BatchInsert do
  @moduledoc false

  alias TowerDB.Repo

  require Logger

  def insert_all([]), do: {:ok, 0}

  def insert_all(events_attrs) when is_list(events_attrs) do
    repo = Repo.repo()
    now = DateTime.utc_now()

    rows =
      Enum.map(events_attrs, fn attrs ->
        %{
          datetime: attrs.datetime,
          level: to_string(attrs.level),
          reason: serialize_term(attrs.reason),
          stacktrace: serialize_term(attrs[:stacktrace]),
          metadata: serialize_term(attrs[:metadata] || %{}),
          inserted_at: now,
          updated_at: now
        }
      end)

    try do
      {count, _} = repo.insert_all("tower_db_events", rows)
      {:ok, count}
    rescue
      e ->
        Logger.error("[TowerDB] Batch insert error: #{Exception.message(e)}")
        {:error, e}
    end
  end

  defp serialize_term(nil), do: nil
  defp serialize_term(term), do: :erlang.term_to_binary(term)
end
