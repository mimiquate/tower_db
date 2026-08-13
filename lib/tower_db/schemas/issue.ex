defmodule TowerDB.Issue do
  use Ecto.Schema

  alias TowerDB.Event

  @primary_key false
  embedded_schema do
    field(:similarity_id, :integer)
    field(:count_occurrences, :integer)
    field(:first_seen, :utc_datetime_usec)
    field(:last_seen, :utc_datetime_usec)
    embeds_one(:last_event, Event)
  end
end
