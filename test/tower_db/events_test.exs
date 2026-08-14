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

    test "filters events by search term" do
      {:ok, _} =
        Events.create_event(%{
          similarity_id: 1,
          datetime: ~U[2026-05-08 10:00:00.000000Z],
          level: :error,
          kind: :message,
          reason: "Database connection failed"
        })

      {:ok, _} =
        Events.create_event(%{
          similarity_id: 2,
          datetime: ~U[2026-05-08 11:00:00.000000Z],
          level: :warning,
          kind: :message,
          reason: "Memory usage high"
        })

      events = Events.list_events(filters: [search: "database"])

      assert length(events) == 1
      assert hd(events).reason == "Database connection failed"
    end

    test "search is case insensitive" do
      {:ok, _} =
        Events.create_event(%{
          similarity_id: 1,
          datetime: ~U[2026-05-08 10:00:00.000000Z],
          level: :error,
          kind: :message,
          reason: "DATABASE ERROR"
        })

      events = Events.list_events(filters: [search: "database"])

      assert length(events) == 1
      assert hd(events).reason == "DATABASE ERROR"
    end

    test "returns empty list when no events match search" do
      {:ok, _} =
        Events.create_event(%{
          similarity_id: 1,
          datetime: ~U[2026-05-08 10:00:00.000000Z],
          level: :error,
          kind: :message,
          reason: "Database connection failed"
        })

      events = Events.list_events(filters: [search: "nonexistent"])

      assert events == []
    end

    test "returns all events when search is empty" do
      {:ok, _} =
        Events.create_event(%{
          similarity_id: 1,
          datetime: ~U[2026-05-08 10:00:00.000000Z],
          level: :error,
          kind: :message,
          reason: "First event"
        })

      {:ok, _} =
        Events.create_event(%{
          similarity_id: 2,
          datetime: ~U[2026-05-08 11:00:00.000000Z],
          level: :warning,
          kind: :message,
          reason: "Second event"
        })

      events = Events.list_events(filters: [search: ""])

      assert length(events) == 2
    end

    test "filters events by level" do
      {:ok, _} =
        Events.create_event(%{
          similarity_id: 1,
          datetime: ~U[2026-05-08 10:00:00.000000Z],
          level: :error,
          kind: :error,
          reason: %DBConnection.ConnectionError{message: "connection is not available"}
        })

      {:ok, _} =
        Events.create_event(%{
          similarity_id: 2,
          datetime: ~U[2026-05-08 11:00:00.000000Z],
          level: :warning,
          kind: :error,
          reason: %ArgumentError{message: "invalid argument"}
        })

      events = Events.list_events(filters: [level: :error])

      assert length(events) == 1
      assert hd(events).level == :error
    end

    test "returns all events when level filter is nil" do
      {:ok, _} =
        Events.create_event(%{
          similarity_id: 1,
          datetime: ~U[2026-05-08 10:00:00.000000Z],
          level: :error,
          kind: :error,
          reason: %DBConnection.ConnectionError{message: "connection is not available"}
        })

      {:ok, _} =
        Events.create_event(%{
          similarity_id: 2,
          datetime: ~U[2026-05-08 11:00:00.000000Z],
          level: :warning,
          kind: :error,
          reason: %ArgumentError{message: "invalid argument"}
        })

      events = Events.list_events(filters: [level: nil])

      assert length(events) == 2
    end

    test "returns empty list when no events match level filter" do
      {:ok, _} =
        Events.create_event(%{
          similarity_id: 1,
          datetime: ~U[2026-05-08 10:00:00.000000Z],
          level: :error,
          kind: :error,
          reason: %DBConnection.ConnectionError{message: "connection is not available"}
        })

      events = Events.list_events(filters: [level: :warning])

      assert events == []
    end

    test "filters events by similarity_id" do
      {:ok, _} =
        Events.create_event(%{
          similarity_id: 1,
          datetime: ~U[2026-05-08 10:00:00.000000Z],
          level: :error,
          kind: :error,
          reason: %DBConnection.ConnectionError{message: "connection is not available"}
        })

      {:ok, _} =
        Events.create_event(%{
          similarity_id: 2,
          datetime: ~U[2026-05-08 11:00:00.000000Z],
          level: :warning,
          kind: :error,
          reason: %ArgumentError{message: "invalid argument"}
        })

      events = Events.list_events(filters: [similarity_id: "1"])

      assert length(events) == 1
      assert hd(events).similarity_id == 1
    end

    test "filters events by a list of similarity_id values" do
      {:ok, _} =
        Events.create_event(%{
          similarity_id: 1,
          datetime: ~U[2026-05-08 10:00:00.000000Z],
          level: :error,
          kind: :error,
          reason: %DBConnection.ConnectionError{message: "connection is not available"}
        })

      {:ok, _} =
        Events.create_event(%{
          similarity_id: 2,
          datetime: ~U[2026-05-08 11:00:00.000000Z],
          level: :warning,
          kind: :error,
          reason: %ArgumentError{message: "invalid argument"}
        })

      {:ok, _} =
        Events.create_event(%{
          similarity_id: 3,
          datetime: ~U[2026-05-08 12:00:00.000000Z],
          level: :warning,
          kind: :error,
          reason: %RuntimeError{message: "unexpected"}
        })

      events = Events.list_events(filters: [similarity_id: ["1", "3"]])

      assert length(events) == 2
      assert Enum.map(events, & &1.similarity_id) |> Enum.sort() == [1, 3]
    end

    test "filters events by level and search term" do
      {:ok, _} =
        Events.create_event(%{
          similarity_id: 1,
          datetime: ~U[2026-05-08 10:00:00.000000Z],
          level: :error,
          kind: :error,
          reason: %DBConnection.ConnectionError{message: "connection is not available"}
        })

      {:ok, _} =
        Events.create_event(%{
          similarity_id: 2,
          datetime: ~U[2026-05-08 11:00:00.000000Z],
          level: :warning,
          kind: :error,
          reason: %DBConnection.ConnectionError{message: "connection is not available"}
        })

      {:ok, _} =
        Events.create_event(%{
          similarity_id: 3,
          datetime: ~U[2026-05-08 12:00:00.000000Z],
          level: :error,
          kind: :error,
          reason: %ArgumentError{message: "invalid argument"}
        })

      events = Events.list_events(filters: [level: :error, search: "connection"])

      assert length(events) == 1

      assert hd(events).reason == %DBConnection.ConnectionError{
               message: "connection is not available"
             }
    end

    test "filters events by datetime range" do
      {:ok, _} =
        Events.create_event(%{
          similarity_id: 1,
          datetime: ~U[2026-05-08 08:00:00.000000Z],
          level: :error,
          kind: :error,
          reason: %RuntimeError{message: "before range"}
        })

      {:ok, _} =
        Events.create_event(%{
          similarity_id: 2,
          datetime: ~U[2026-05-08 10:00:00.000000Z],
          level: :error,
          kind: :error,
          reason: %RuntimeError{message: "inside range"}
        })

      {:ok, _} =
        Events.create_event(%{
          similarity_id: 3,
          datetime: ~U[2026-05-08 14:00:00.000000Z],
          level: :error,
          kind: :error,
          reason: %RuntimeError{message: "after range"}
        })

      from = ~U[2026-05-08 09:00:00.000000Z]
      to = ~U[2026-05-08 12:00:00.000000Z]

      events = Events.list_events(filters: [datetime_range: {from, to}])

      assert length(events) == 1
      assert hd(events).reason == %RuntimeError{message: "inside range"}
    end

    test "datetime range is inclusive on both ends" do
      from = ~U[2026-05-08 09:00:00.000000Z]
      to = ~U[2026-05-08 12:00:00.000000Z]

      {:ok, _} =
        Events.create_event(%{
          similarity_id: 1,
          datetime: from,
          level: :error,
          kind: :error,
          reason: %RuntimeError{message: "at from"}
        })

      {:ok, _} =
        Events.create_event(%{
          similarity_id: 2,
          datetime: to,
          level: :error,
          kind: :error,
          reason: %RuntimeError{message: "at to"}
        })

      events = Events.list_events(filters: [datetime_range: {from, to}])

      assert length(events) == 2
    end

    test "returns empty list when no events match datetime range" do
      {:ok, _} =
        Events.create_event(%{
          similarity_id: 1,
          datetime: ~U[2026-05-08 08:00:00.000000Z],
          level: :error,
          kind: :error,
          reason: %RuntimeError{message: "outside range"}
        })

      from = ~U[2026-05-08 09:00:00.000000Z]
      to = ~U[2026-05-08 12:00:00.000000Z]

      events = Events.list_events(filters: [datetime_range: {from, to}])

      assert events == []
    end

    test "filters events by datetime range and level" do
      from = ~U[2026-05-08 09:00:00.000000Z]
      to = ~U[2026-05-08 12:00:00.000000Z]

      {:ok, _} =
        Events.create_event(%{
          similarity_id: 1,
          datetime: ~U[2026-05-08 10:00:00.000000Z],
          level: :error,
          kind: :error,
          reason: %RuntimeError{message: "matches both"}
        })

      {:ok, _} =
        Events.create_event(%{
          similarity_id: 2,
          datetime: ~U[2026-05-08 10:00:00.000000Z],
          level: :warning,
          kind: :error,
          reason: %RuntimeError{message: "wrong level"}
        })

      events = Events.list_events(filters: [datetime_range: {from, to}, level: :error])

      assert length(events) == 1
      assert hd(events).reason == %RuntimeError{message: "matches both"}
    end

    test "filters events by datetime range and search term" do
      from = ~U[2026-05-08 09:00:00.000000Z]
      to = ~U[2026-05-08 12:00:00.000000Z]

      {:ok, _} =
        Events.create_event(%{
          similarity_id: 1,
          datetime: ~U[2026-05-08 10:00:00.000000Z],
          level: :error,
          kind: :error,
          reason: %RuntimeError{message: "database connection failed"}
        })

      {:ok, _} =
        Events.create_event(%{
          similarity_id: 2,
          datetime: ~U[2026-05-08 10:00:00.000000Z],
          level: :error,
          kind: :error,
          reason: %RuntimeError{message: "memory usage high"}
        })

      events = Events.list_events(filters: [datetime_range: {from, to}, search: "database"])

      assert length(events) == 1
      assert hd(events).reason == %RuntimeError{message: "database connection failed"}
    end

    test "filters events by datetime range, level, and search term" do
      from = ~U[2026-05-08 09:00:00.000000Z]
      to = ~U[2026-05-08 12:00:00.000000Z]

      {:ok, _} =
        Events.create_event(%{
          similarity_id: 1,
          datetime: ~U[2026-05-08 10:00:00.000000Z],
          level: :error,
          kind: :error,
          reason: %RuntimeError{message: "database timeout"}
        })

      {:ok, _} =
        Events.create_event(%{
          similarity_id: 2,
          datetime: ~U[2026-05-08 10:00:00.000000Z],
          level: :warning,
          kind: :error,
          reason: %RuntimeError{message: "database timeout"}
        })

      {:ok, _} =
        Events.create_event(%{
          similarity_id: 3,
          datetime: ~U[2026-05-08 14:00:00.000000Z],
          level: :error,
          kind: :error,
          reason: %RuntimeError{message: "database timeout"}
        })

      events =
        Events.list_events(
          filters: [datetime_range: {from, to}, level: :error, search: "timeout"]
        )

      assert length(events) == 1
      assert hd(events).similarity_id == 1
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
