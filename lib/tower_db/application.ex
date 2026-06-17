defmodule TowerDB.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Storage must start first as it owns the ETS table
      TowerDB.CircuitBreaker.Storage,
      TowerDB.CircuitBreaker,
      TowerDB.Buffer
    ]

    opts = [strategy: :one_for_one, name: TowerDB.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
