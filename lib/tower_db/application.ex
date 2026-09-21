defmodule TowerDB.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = pruner_children() ++ burst_protector_children()

    Supervisor.start_link(children, strategy: :one_for_one, name: TowerDB.Supervisor)
  end

  defp pruner_children do
    case Application.get_env(:tower_db, :pruner, []) do
      false -> []
      opts when is_list(opts) -> [{TowerDB.Pruner, opts}]
    end
  end

  defp burst_protector_children do
    opts = Application.get_env(:tower_db, :burst_protection, [])
    [{TowerDB.BurstProtector, opts}]
  end
end
