defmodule TowerDB.Event do
  use Ecto.Schema

  import Ecto.Changeset

  schema "tower_db_events" do
    field(:similarity_id, :integer)
    field(:datetime, :utc_datetime_usec)

    field(:level, Ecto.Enum,
      values: [:debug, :info, :emergency, :alert, :critical, :error, :warning, :notice]
    )

    field(:kind, Ecto.Enum, values: [:error, :exit, :throw, :message])
    field(:reason, TowerDB.Types.Term)
    field(:normalized_reason, :string)
    field(:stacktrace, TowerDB.Types.Term)
    field(:log_event, TowerDB.Types.Term)
    field(:plug_conn, TowerDB.Types.Term)
    field(:metadata, TowerDB.Types.Term)
    field(:by, :string)

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(event, attrs) do
    event
    |> cast(attrs, [
      :similarity_id,
      :datetime,
      :level,
      :kind,
      :reason,
      :stacktrace,
      :log_event,
      :plug_conn,
      :metadata,
      :by
    ])
    |> validate_required([:similarity_id, :datetime, :level, :kind, :reason])
    |> put_normalized_reason()
  end

  defp put_normalized_reason(changeset) do
    reason = get_field(changeset, :reason)
    kind = get_field(changeset, :kind)
    stacktrace = get_field(changeset, :stacktrace) || []
    normalized_reason = format_reason(kind, reason, stacktrace)
    put_change(changeset, :normalized_reason, normalized_reason)
  end

  # Exception.format/3 only handles :error, :exit, and :throw kinds.
  # :message is a Tower-specific kind for manually reported messages,
  # so we handle it separately.
  defp format_reason(:message, reason, _stacktrace), do: reason
  defp format_reason(kind, reason, stacktrace), do: Exception.format(kind, reason, stacktrace)
end
