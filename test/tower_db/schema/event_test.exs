defmodule TowerDB.EventTest do
  use ExUnit.Case, async: true

  alias TowerDB.Event

  describe "changeset/2" do
    test "valid with required fields" do
      attrs = %{
        similarity_id: 12345,
        datetime: ~U[2026-04-16 12:00:00.000000Z],
        level: :error,
        kind: :error,
        reason: %{message: "Something went wrong"}
      }

      changeset = Event.changeset(%Event{}, attrs)

      assert changeset.valid?
      assert changeset.changes.datetime == ~U[2026-04-16 12:00:00.000000Z]
      assert changeset.changes.level == :error
      assert changeset.changes.kind == :error
      assert changeset.changes.reason == %{message: "Something went wrong"}
      assert changeset.changes.similarity_id == 12345
    end

    test "invalid without required fields" do
      changeset = Event.changeset(%Event{}, %{})

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).similarity_id
      assert "can't be blank" in errors_on(changeset).datetime
      assert "can't be blank" in errors_on(changeset).level
      assert "can't be blank" in errors_on(changeset).kind
      assert "can't be blank" in errors_on(changeset).reason
      assert "can't be blank" in errors_on(changeset).similarity_id
    end
  end

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
  end
end
