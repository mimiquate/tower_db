defmodule TowerDB.Pruner do
  use GenServer

  import Ecto.Query

  alias TowerDB.Event
  alias TowerDB.Events
  alias TowerDB.Repo
  alias __MODULE__, as: State

  defstruct timer: nil,
            repo: nil,
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

  @impl true
  def terminate(_reason, state) do
    if is_reference(state.timer), do: Process.cancel_timer(state.timer)

    :ok
  end

  defp schedule_prune(state) do
    %{state | timer: Process.send_after(self(), :prune, state.interval)}
  end

  defp to_seconds({amount, :seconds}), do: amount
  defp to_seconds({amount, :minutes}), do: amount * 60
  defp to_seconds({amount, :hours}), do: amount * 3_600
  defp to_seconds({amount, :days}), do: amount * 86_400

  defp prune_by_age(state) do
    cutoff = DateTime.add(DateTime.utc_now(), -state.max_age, :second)
    delete_in_batches(state, where(Event, [e], e.datetime < ^cutoff))
  end

  defp prune_by_issue_size(state) do
    case state.max_size_per_issue do
      :infinity -> :ok
      max_count -> delete_in_batches(state, over_limit_issue_events(max_count))
    end
  end

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

  defp prune_by_total_size(state) do
    case state.max_size do
      :infinity ->
        :ok

      max_count ->
        overage = Events.count_events(repo: state.repo) - max_count
        if overage > 0, do: delete_in_batches(state, Event, overage), else: :ok
    end
  end

  # `remaining` is either `:unbounded` (delete everything matching, e.g. age-based
  # pruning) or the known number of rows still to delete (size-based pruning),
  defp delete_in_batches(state, queryable, remaining \\ :unbounded) do
    limit =
      case remaining do
        :unbounded -> state.batch_size
        n -> min(n, state.batch_size)
      end

    ids =
      queryable
      |> order_by(asc: :datetime)
      |> limit(^limit)
      |> select([e], e.id)
      |> state.repo.all()

    case ids do
      [] ->
        :ok

      ids ->
        Events.delete_events(ids, repo: state.repo)

        case remaining do
          :unbounded ->
            delete_in_batches(state, queryable, :unbounded)

          n ->
            case n - length(ids) do
              left when left <= 0 -> :ok
              left -> delete_in_batches(state, queryable, left)
            end
        end
    end
  end
end
