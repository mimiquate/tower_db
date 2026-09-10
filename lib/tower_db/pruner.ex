defmodule TowerDB.Pruner do
  use GenServer

  require Logger

  import Ecto.Query

  alias TowerDB.Event
  alias TowerDB.Events
  alias TowerDB.Repo

  @default_max_age 7_776_000
  @default_max_size 100_000
  @default_max_size_per_issue 1_000
  @default_interval 30
  @default_batch_size 1_000

  defp config(key, default) do
    :tower_db
    |> Application.get_env(:pruner, [])
    |> Keyword.get(key, default)
  end

  defp max_age, do: config(:max_age, @default_max_age)
  defp max_size, do: config(:max_size, @default_max_size)
  defp max_size_per_issue, do: config(:max_size_per_issue, @default_max_size_per_issue)
  defp interval, do: config(:interval, @default_interval)
  defp batch_size, do: config(:batch_size, @default_batch_size)

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @impl true
  def init(opts) do
    schedule_next()
    {:ok, opts}
  end

  @impl true
  def handle_info(:prune, opts) do
    prune(opts)
    schedule_next()
    {:noreply, opts}
  end

  defp schedule_next do
    Process.send_after(self(), :prune, interval() * 1_000)
  end

  def prune(opts \\ []) do
    repo = Keyword.get(opts, :repo) || Repo.repo()

    prune_by_age(repo)
    prune_by_issue_size(repo)
    prune_by_total_size(repo)

    :ok
  end

  defp prune_by_age(repo) do
    cutoff = DateTime.add(DateTime.utc_now(), -max_age(), :second)
    delete_in_batches(repo, where(Event, [e], e.datetime < ^cutoff))
  end

  defp prune_by_issue_size(repo) do
    case max_size_per_issue() do
      :infinity -> :ok
      max_count -> delete_in_batches(repo, over_limit_issue_events(max_count))
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

  defp prune_by_total_size(repo) do
    case max_size() do
      :infinity ->
        :ok

      max_count ->
        overage = Events.count_events(repo: repo) - max_count
        delete_in_batches(repo, Event, overage)
    end
  end

  # `remaining` is either `:unbounded` (delete everything matching, e.g. age-based
  # pruning) or the known number of rows still to delete (size-based pruning),
  defp delete_in_batches(repo, queryable, remaining \\ :unbounded) do
    limit =
      case remaining do
        :unbounded -> batch_size()
        n when n <= 0 -> 0
        n -> min(n, batch_size())
      end

    ids =
      queryable
      |> order_by(asc: :datetime)
      |> limit(^limit)
      |> select([e], e.id)
      |> repo.all()

    case ids do
      [] ->
        :ok

      ids ->
        Events.delete_events(ids, repo: repo)
        Logger.info("TowerDB.Pruner deleted #{length(ids)} event(s)")

        case remaining do
          :unbounded -> delete_in_batches(repo, queryable, :unbounded)
          n -> delete_in_batches(repo, queryable, n - length(ids))
        end
    end
  end
end
