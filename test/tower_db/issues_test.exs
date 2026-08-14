defmodule TowerDB.IssuesTest do
  use TowerDB.DataCase, async: false

  alias TowerDB.Events
  alias TowerDB.Issues

  describe "list_issues/1" do
    test "lists distinct issues grouped by similarity_id" do
      {:ok, _} =
        Events.create_event(%{
          similarity_id: 1,
          datetime: ~U[2026-05-08 10:00:00.000000Z],
          level: :error,
          kind: :error,
          reason: %RuntimeError{message: "first occurrence of error A"}
        })

      {:ok, _} =
        Events.create_event(%{
          similarity_id: 1,
          datetime: ~U[2026-05-08 12:00:00.000000Z],
          level: :error,
          kind: :error,
          reason: %RuntimeError{message: "second occurrence of error A"}
        })

      {:ok, _} =
        Events.create_event(%{
          similarity_id: 2,
          datetime: ~U[2026-05-08 11:00:00.000000Z],
          level: :warning,
          kind: :error,
          reason: %ArgumentError{message: "error B"}
        })

      issues = Issues.list_issues()

      assert length(issues) == 2

      issue_a = Enum.find(issues, &(&1.similarity_id == 1))
      issue_b = Enum.find(issues, &(&1.similarity_id == 2))

      assert issue_a.count_occurrences == 2
      assert issue_a.first_seen == ~U[2026-05-08 10:00:00.000000Z]
      assert issue_a.last_seen == ~U[2026-05-08 12:00:00.000000Z]
      assert issue_a.last_event.reason == %RuntimeError{message: "second occurrence of error A"}

      assert issue_b.count_occurrences == 1
      assert issue_b.first_seen == ~U[2026-05-08 11:00:00.000000Z]
      assert issue_b.last_seen == ~U[2026-05-08 11:00:00.000000Z]
      assert issue_b.last_event.reason == %ArgumentError{message: "error B"}
    end

    test "returns all issues without filters and only matching ones with a search filter" do
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

      assert length(Issues.list_issues()) == 2

      issues = Issues.list_issues(filters: [search: "database"])

      assert length(issues) == 1
      assert hd(issues).similarity_id == 1
    end
  end
end
