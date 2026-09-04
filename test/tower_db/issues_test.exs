defmodule TowerDB.IssuesTest do
  use TowerDB.DataCase, async: false

  alias TowerDB.Events
  alias TowerDB.Issues

  describe "list_issues/1" do
    test "lists distinct issues grouped by similarity_id" do
      {:ok, _} =
        Events.create_event(%{
          id: UUIDv7.generate(),
          similarity_id: 1,
          datetime: ~U[2026-05-08 10:00:00.000000Z],
          level: :error,
          kind: :error,
          reason: %RuntimeError{message: "first occurrence of error A"}
        })

      {:ok, _} =
        Events.create_event(%{
          id: UUIDv7.generate(),
          similarity_id: 1,
          datetime: ~U[2026-05-08 12:00:00.000000Z],
          level: :error,
          kind: :error,
          reason: %RuntimeError{message: "second occurrence of error A"}
        })

      {:ok, _} =
        Events.create_event(%{
          id: UUIDv7.generate(),
          similarity_id: 2,
          datetime: ~U[2026-05-08 11:00:00.000000Z],
          level: :warning,
          kind: :error,
          reason: %ArgumentError{message: "error B"}
        })

      issues = Issues.list_issues()

      assert length(issues) == 2

      issue_a = Enum.find(issues, &(&1.id == 1))
      issue_b = Enum.find(issues, &(&1.id == 2))

      assert issue_a.count_events == 2
      assert issue_a.first_seen == ~U[2026-05-08 10:00:00.000000Z]
      assert issue_a.last_seen == ~U[2026-05-08 12:00:00.000000Z]
      assert issue_a.last_event.normalized_reason =~ "second occurrence of error A"

      assert issue_b.count_events == 1
      assert issue_b.first_seen == ~U[2026-05-08 11:00:00.000000Z]
      assert issue_b.last_seen == ~U[2026-05-08 11:00:00.000000Z]
      assert issue_b.last_event.normalized_reason =~ "error B"
    end

    test "returns all issues without filters and only matching ones with a search filter" do
      {:ok, _} =
        Events.create_event(%{
          id: UUIDv7.generate(),
          similarity_id: 1,
          datetime: ~U[2026-05-08 10:00:00.000000Z],
          level: :error,
          kind: :message,
          reason: "Database connection failed"
        })

      {:ok, _} =
        Events.create_event(%{
          id: UUIDv7.generate(),
          similarity_id: 2,
          datetime: ~U[2026-05-08 11:00:00.000000Z],
          level: :warning,
          kind: :message,
          reason: "Memory usage high"
        })

      assert length(Issues.list_issues()) == 2

      issues = Issues.list_issues(filters: [search: "database"])

      assert length(issues) == 1
      assert hd(issues).id == 1
    end

    test "paginates results with limit and offset" do
      {:ok, _} =
        Events.create_event(%{
          id: UUIDv7.generate(),
          similarity_id: 1,
          datetime: ~U[2026-05-08 10:00:00.000000Z],
          level: :error,
          kind: :error,
          reason: %RuntimeError{message: "error A"}
        })

      {:ok, _} =
        Events.create_event(%{
          id: UUIDv7.generate(),
          similarity_id: 2,
          datetime: ~U[2026-05-08 11:00:00.000000Z],
          level: :warning,
          kind: :error,
          reason: %ArgumentError{message: "error B"}
        })

      {:ok, _} =
        Events.create_event(%{
          id: UUIDv7.generate(),
          similarity_id: 3,
          datetime: ~U[2026-05-08 12:00:00.000000Z],
          level: :error,
          kind: :error,
          reason: %RuntimeError{message: "error C"}
        })

      page_1 = Issues.list_issues(limit: 2, offset: 0)
      page_2 = Issues.list_issues(limit: 2, offset: 2)

      assert Enum.map(page_1, & &1.id) == [3, 2]
      assert Enum.map(page_2, & &1.id) == [1]
    end

    test "orders issues by last_seen descending" do
      {:ok, _} =
        Events.create_event(%{
          id: UUIDv7.generate(),
          similarity_id: 1,
          datetime: ~U[2026-05-08 10:00:00.000000Z],
          level: :error,
          kind: :error,
          reason: %RuntimeError{message: "error A"}
        })

      {:ok, _} =
        Events.create_event(%{
          id: UUIDv7.generate(),
          similarity_id: 2,
          datetime: ~U[2026-05-08 12:00:00.000000Z],
          level: :warning,
          kind: :error,
          reason: %ArgumentError{message: "error B"}
        })

      {:ok, _} =
        Events.create_event(%{
          id: UUIDv7.generate(),
          similarity_id: 3,
          datetime: ~U[2026-05-08 11:00:00.000000Z],
          level: :error,
          kind: :error,
          reason: %RuntimeError{message: "error C"}
        })

      issues = Issues.list_issues()

      assert Enum.map(issues, & &1.id) == [2, 3, 1]
    end

    test "count_events, first_seen and last_seen are not scoped to the datetime_range filter" do
      now = DateTime.utc_now() |> DateTime.truncate(:microsecond)
      outside_window = DateTime.add(now, -10, :day)
      another_outside_window = DateTime.add(now, -5, :day)
      inside_window = DateTime.add(now, -1, :hour)

      {:ok, _} =
        Events.create_event(%{
          id: UUIDv7.generate(),
          similarity_id: 1,
          datetime: outside_window,
          level: :error,
          kind: :message,
          reason: "Older occurrence outside the filtered window"
        })

      {:ok, _} =
        Events.create_event(%{
          id: UUIDv7.generate(),
          similarity_id: 1,
          datetime: another_outside_window,
          level: :error,
          kind: :message,
          reason: "Another occurrence outside the filtered window"
        })

      {:ok, _} =
        Events.create_event(%{
          id: UUIDv7.generate(),
          similarity_id: 1,
          datetime: inside_window,
          level: :error,
          kind: :message,
          reason: "Recent occurrence inside the filtered window"
        })

      datetime_range = {DateTime.add(now, -2, :hour), now}

      [issue] = Issues.list_issues(filters: [datetime_range: datetime_range])

      assert issue.count_events == 3
      assert issue.first_seen == outside_window
      assert issue.last_seen == inside_window
      assert issue.last_event.normalized_reason == "Recent occurrence inside the filtered window"
    end
  end

  describe "get_issue/2" do
    test "returns the issue matching the given id" do
      {:ok, _} =
        Events.create_event(%{
          id: UUIDv7.generate(),
          similarity_id: 1,
          datetime: ~U[2026-05-08 10:00:00.000000Z],
          level: :error,
          kind: :error,
          reason: %RuntimeError{message: "first occurrence of error A"}
        })

      {:ok, _} =
        Events.create_event(%{
          id: UUIDv7.generate(),
          similarity_id: 1,
          datetime: ~U[2026-05-08 12:00:00.000000Z],
          level: :error,
          kind: :error,
          reason: %RuntimeError{message: "second occurrence of error A"}
        })

      {:ok, _} =
        Events.create_event(%{
          id: UUIDv7.generate(),
          similarity_id: 2,
          datetime: ~U[2026-05-08 11:00:00.000000Z],
          level: :warning,
          kind: :error,
          reason: %ArgumentError{message: "error B"}
        })

      issue = Issues.get_issue(1)

      assert issue.id == 1
      assert issue.count_events == 2
      assert issue.last_event.normalized_reason =~ "second occurrence of error A"
    end
  end

  describe "count_issues/1" do
    test "counts distinct similarity_ids, not total events, and respects filters" do
      {:ok, _} =
        Events.create_event(%{
          id: UUIDv7.generate(),
          similarity_id: 1,
          datetime: ~U[2026-05-08 10:00:00.000000Z],
          level: :error,
          kind: :error,
          reason: %RuntimeError{message: "first occurrence of error A"}
        })

      {:ok, _} =
        Events.create_event(%{
          id: UUIDv7.generate(),
          similarity_id: 1,
          datetime: ~U[2026-05-08 11:00:00.000000Z],
          level: :error,
          kind: :error,
          reason: %RuntimeError{message: "second occurrence of error A"}
        })

      {:ok, _} =
        Events.create_event(%{
          id: UUIDv7.generate(),
          similarity_id: 2,
          datetime: ~U[2026-05-08 12:00:00.000000Z],
          level: :warning,
          kind: :error,
          reason: %ArgumentError{message: "error B"}
        })

      assert Issues.count_issues() == 2
      assert Issues.count_issues(filters: [level: :warning]) == 1
    end
  end
end
