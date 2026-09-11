defmodule TowerDB.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      if Application.get_env(:tower_db, :pruner), do: [TowerDB.Pruner], else: []

    Supervisor.start_link(children, strategy: :one_for_one, name: TowerDB.Supervisor)
  end
end
