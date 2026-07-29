defmodule TowerDB.EventsTest do
  use TowerDB.DataCase, async: false

  alias TowerDB.Events

  describe "create_event/1" do
    test "creates an event with valid attrs" do
      attrs = %{
        similarity_id: 12345,
        datetime: ~U[2026-04-16 12:00:00.000000Z],
        level: :error,
        kind: :error,
        reason: %RuntimeError{message: "Something went wrong"}
      }

      assert {:ok, event} = Events.create_event(attrs)
      assert event.datetime == ~U[2026-04-16 12:00:00.000000Z]
      assert event.level == :error
      assert event.kind == :error
      assert event.reason == %RuntimeError{message: "Something went wrong"}
      assert event.similarity_id == 12345
    end

    test "returns error with invalid attrs" do
      assert {:error, _} = Events.create_event(%{})
    end
  end

  describe "list_events/1" do
    test "returns events ordered by datetime descending" do
      assert Events.list_events() == []

      {:ok, _} =
        Events.create_event(%{
          similarity_id: 1,
          datetime: ~U[2026-05-08 10:00:00.000000Z],
          level: :error,
          kind: :error,
          reason: %ArgumentError{message: "first"}
        })

      {:ok, _} =
        Events.create_event(%{
          similarity_id: 2,
          datetime: ~U[2026-05-08 12:00:00.000000Z],
          level: :error,
          kind: :error,
          reason: %RuntimeError{message: "third"}
        })

      {:ok, _} =
        Events.create_event(%{
          similarity_id: 3,
          datetime: ~U[2026-05-08 11:00:00.000000Z],
          level: :warning,
          kind: :message,
          reason: "second"
        })

      events = Events.list_events()

      assert length(events) == 3

      assert Enum.map(events, & &1.reason) == [
               %RuntimeError{message: "third"},
               "second",
               %ArgumentError{message: "first"}
             ]
    end
  end

  describe "delete_event/2" do
    test "deletes an existing event" do
      {:ok, event} =
        Events.create_event(%{
          similarity_id: 99,
          datetime: ~U[2026-04-16 12:00:00.000000Z],
          level: :warning,
          kind: :message,
          reason: "to be deleted"
        })

      assert {:ok, deleted_event} = Events.delete_event(event)
      assert deleted_event.id == event.id
      assert Events.list_events() == []
    end
  end
end
