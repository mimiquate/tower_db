defmodule TowerDB.EventsTest do
  use TowerDB.DataCase, async: false

  alias TowerDB.Events

  describe "create_event/1" do
    test "creates an event with valid attrs" do
      attrs = %{
        datetime: ~U[2026-04-16 12:00:00.000000Z],
        level: :error,
        reason: %RuntimeError{message: "Something went wrong"}
      }

      assert {:ok, event} = Events.create_event(attrs)
      assert event.datetime == ~U[2026-04-16 12:00:00.000000Z]
      assert event.level == :error
      assert event.reason == %RuntimeError{message: "Something went wrong"}
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
          datetime: ~U[2026-05-08 10:00:00.000000Z],
          level: :error,
          reason: "first"
        })

      {:ok, _} =
        Events.create_event(%{
          datetime: ~U[2026-05-08 12:00:00.000000Z],
          level: :error,
          reason: "third"
        })

      {:ok, _} =
        Events.create_event(%{
          datetime: ~U[2026-05-08 11:00:00.000000Z],
          level: :error,
          reason: "second"
        })

      events = Events.list_events()

      assert length(events) == 3
      assert Enum.map(events, & &1.reason) == ["third", "second", "first"]
    end
  end

  describe "delete_event/2" do
    test "deletes an existing event" do
      {:ok, event} =
        Events.create_event(%{
          datetime: ~U[2026-04-16 12:00:00.000000Z],
          level: :error,
          reason: "to be deleted"
        })

      assert {:ok, deleted_event} = Events.delete_event(event)
      assert deleted_event.id == event.id
      assert Events.list_events() == []
    end
  end
end
