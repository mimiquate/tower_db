defmodule TowerDB.DataCase do
  use ExUnit.CaseTemplate

  setup do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(TowerDB.TestRepo, shared: true)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
    :ok
  end
end
