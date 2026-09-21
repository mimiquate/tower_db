defmodule TowerDB.Pruner do
  use GenServer

  import Ecto.Query

  alias TowerDB.Event
  alias TowerDB.Events
  alias TowerDB.Repo
  alias __MODULE__, as: State

  defstruct repo: nil,
            max_age: {90, :days},
            max_size: 100_000,
            max_size_per_issue: 1_000,
            interval: {30, :seconds},
            batch_size: 1_000

  def start_link(opts \\ []) do
    state = struct!(State, opts)

    state = %{
      state
      | repo: Repo.repo(),
        max_age: to_seconds(state.max_age),
        interval: to_seconds(state.interval) * 1_000
    }

    GenServer.start_link(__MODULE__, state, name: __MODULE__)
  end

  @impl true
  def init(state) do
    {:ok, schedule_prune(state)}
  end

  @impl true
  def handle_info(:prune, state) do
    prune_by_age(state)
    prune_by_issue_size(state)
    prune_by_total_size(state)

    {:noreply, schedule_prune(state)}
  end

  def handle_info(_message, state) do
    {:noreply, state}
  end

  defp schedule_prune(state) do
    Process.send_after(self(), :prune, state.interval)
    state
  end

  defp to_seconds(:infinity), do: :infinity
  defp to_seconds({amount, :seconds}), do: amount
  defp to_seconds({amount, :minutes}), do: amount * 60
  defp to_seconds({amount, :hours}), do: amount * 3_600
  defp to_seconds({amount, :days}), do: amount * 86_400

  defp prune_by_age(%State{max_age: :infinity}), do: :ok

  defp prune_by_age(state) do
    cutoff = DateTime.add(DateTime.utc_now(), -state.max_age, :second)
    delete_in_batches(state, where(Event, [e], e.datetime < ^cutoff))
  end

  defp prune_by_issue_size(%State{max_size_per_issue: :infinity}), do: :ok

  defp prune_by_issue_size(state),
    do: delete_in_batches(state, over_limit_issue_events(state.max_size_per_issue))

  defp over_limit_issue_events(max_count) do
    Event
    |> select([e], %{
      id: e.id,
      datetime: e.datetime,
      rank: over(row_number(), partition_by: e.similarity_id, order_by: [desc: e.datetime])
    })
    |> subquery()
    |> where([r], r.rank > ^max_count)
  end

  defp prune_by_total_size(%State{max_size: :infinity}), do: :ok
  defp prune_by_total_size(state), do: delete_in_batches(state, over_limit_events(state.max_size))

  defp over_limit_events(max_count) do
    Event
    |> select([e], %{
      id: e.id,
      datetime: e.datetime,
      rank: over(row_number(), order_by: [desc: e.datetime])
    })
    |> subquery()
    |> where([r], r.rank > ^max_count)
  end

  defp delete_in_batches(state, queryable) do
    ids =
      queryable
      |> order_by(asc: :datetime)
      |> limit(^state.batch_size)
      |> select([e], e.id)
      |> state.repo.all()

    case Events.delete_events(ids, repo: state.repo) do
      {0, nil} -> :ok
      {_count, nil} -> delete_in_batches(state, queryable)
    end
  end
end
