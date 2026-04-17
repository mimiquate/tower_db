defmodule TowerDB.EventsTest do
  use ExUnit.Case, async: true

  alias TowerDB.Events

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(TowerDB.TestRepo)
  end

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
end
