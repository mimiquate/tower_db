defmodule TowerDB.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      TowerDB.CleanupServer
    ]

    opts = [strategy: :one_for_one, name: TowerDB.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
