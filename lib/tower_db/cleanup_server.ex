defmodule TowerDB.CleanupServer do
  @moduledoc """
  A GenServer that periodically cleans up old events based on the configured cleanup strategy.

  Only starts if `cleanup_strategy` is set to `{:automatic, older_than: N, run_every: M}`.
  """

  use GenServer

  alias TowerDB.Events
  alias TowerDB.Repo

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    strategy = Keyword.get(opts, :cleanup_strategy) || Repo.cleanup_strategy()

    case strategy do
      {:automatic, config} when is_list(config) ->
        older_than = Keyword.get(config, :older_than)
        run_every = Keyword.get(config, :run_every)

        cond do
          is_nil(older_than) and is_nil(run_every) ->
            raise ArgumentError,
                  "cleanup_strategy: :automatic requires both :older_than and :run_every options. " <>
                    "Example: cleanup_strategy: {:automatic, older_than: 90, run_every: 5}"

          is_nil(older_than) ->
            raise ArgumentError,
                  "cleanup_strategy: :automatic requires :older_than option. " <>
                    "Example: cleanup_strategy: {:automatic, older_than: 90, run_every: 5}"

          is_nil(run_every) ->
            raise ArgumentError,
                  "cleanup_strategy: :automatic requires :run_every option. " <>
                    "Example: cleanup_strategy: {:automatic, older_than: 90, run_every: 5}"

          true ->
            interval_ms = days_to_ms(run_every)
            schedule_cleanup(interval_ms)
            {:ok, %{older_than: older_than, interval_ms: interval_ms, repo: Keyword.get(opts, :repo)}}
        end

      strategy when strategy in [nil, :manual] ->
        :ignore

      invalid ->
        raise ArgumentError,
              "Invalid cleanup_strategy: #{inspect(invalid)}. " <>
                "Expected :manual or {:automatic, older_than: days, run_every: days}. " <>
                "Example: cleanup_strategy: {:automatic, older_than: 90, run_every: 5}"
    end
  end

  defp days_to_ms(days) do
    trunc(days * 24 * 60 * 60 * 1000)
  end

  @impl true
  def handle_info(:cleanup, state) do
    opts = if state.repo, do: [repo: state.repo, days: state.older_than], else: [days: state.older_than]
    Events.prune_old(opts)

    schedule_cleanup(state.interval_ms)

    {:noreply, state}
  end

  defp schedule_cleanup(interval_ms) do
    Process.send_after(self(), :cleanup, interval_ms)
  end
end
