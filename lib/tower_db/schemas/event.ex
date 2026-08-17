defmodule TowerDB.Event do
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, UUIDv7.Type, autogenerate: false}

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
    field(:metadata, TowerDB.Types.Term)

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(event, attrs) do
    event
    |> cast(attrs, [
      :id,
      :similarity_id,
      :datetime,
      :level,
      :kind,
      :reason,
      :stacktrace,
      :metadata
    ])
    |> validate_required([:id, :similarity_id, :datetime, :level, :kind, :reason])
    |> put_normalized_reason()
  end

  defp put_normalized_reason(changeset) do
    if changeset.valid? do
      kind = get_field(changeset, :kind)
      reason = get_field(changeset, :reason)
      stacktrace = get_field(changeset, :stacktrace) || []
      normalized_reason = format_reason(kind, reason, stacktrace)
      put_change(changeset, :normalized_reason, normalized_reason)
    else
      changeset
    end
  end

  # Exception.format/3 only handles :error, :exit, and :throw kinds.
  # :message is a Tower-specific kind for manually reported messages,
  # so we handle it separately.
  defp format_reason(:message, reason, _stacktrace), do: reason
  defp format_reason(kind, reason, stacktrace), do: Exception.format(kind, reason, stacktrace)
end
