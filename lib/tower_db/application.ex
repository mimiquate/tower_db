defmodule TowerDB.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Task.Supervisor, name: TowerDB.TaskSupervisor, max_children: 5},
      TowerDB.Buffer
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: TowerDB.Supervisor)
  end
end
