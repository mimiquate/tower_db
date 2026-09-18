defmodule TowerDB.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      case Application.get_env(:tower_db, :pruner, []) do
        false -> []
        opts when is_list(opts) -> [{TowerDB.Pruner, opts}]
      end

    Supervisor.start_link(children, strategy: :one_for_one, name: TowerDB.Supervisor)
  end
end
