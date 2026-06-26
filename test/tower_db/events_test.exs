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

  describe "max_events enforcement" do
    test "deletes oldest events when exceeding max_events limit" do
      # Create 5 events with max_events: 5, all should be kept
      for i <- 1..5 do
        {:ok, _} =
          Events.create_event(
            %{
              datetime: DateTime.add(~U[2026-05-08 10:00:00.000000Z], i, :hour),
              level: :error,
              reason: "event_#{i}"
            },
            max_events: 5
          )
      end

      assert length(Events.list_events()) == 5

      # Create 6th event with max_events: 5, should delete the oldest
      {:ok, _} =
        Events.create_event(
          %{
            datetime: ~U[2026-05-08 16:00:00.000000Z],
            level: :error,
            reason: "event_6"
          },
          max_events: 5
        )

      events = Events.list_events()
      assert length(events) == 5

      reasons = Enum.map(events, & &1.reason)
      refute "event_1" in reasons
      assert "event_6" in reasons
    end

    test "keeps all events when max_events is not configured" do
      # Create 10 events without max_events config
      for i <- 1..10 do
        {:ok, _} =
          Events.create_event(%{
            datetime: DateTime.add(~U[2026-05-08 10:00:00.000000Z], i, :hour),
            level: :error,
            reason: "event_#{i}"
          })
      end

      # All 10 events should be kept since no limit is configured
      events = Events.list_events()
      assert length(events) == 10
    end
  end
end
