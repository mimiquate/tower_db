defmodule TowerDB.CircuitBreakerTest do
  use ExUnit.Case, async: false

  alias TowerDB.CircuitBreaker
  alias TowerDB.CircuitBreaker.Storage

  @processes [CircuitBreaker, Storage]

  setup do
    stop_supervisor()
    stop_processes(@processes)

    {:ok, _} = Storage.start_link()
    {:ok, _} = CircuitBreaker.start_link()

    on_exit(fn ->
      safe_call(CircuitBreaker, :reset)
      stop_processes(@processes)
    end)

    :ok
  end

  defp stop_supervisor do
    case Process.whereis(TowerDB.Supervisor) do
      nil -> :ok
      pid -> Supervisor.stop(pid)
    end
  end

  defp stop_processes(names) do
    for name <- names do
      case Process.whereis(name) do
        nil -> :ok
        pid ->
          try do
            GenServer.stop(pid, :normal, 100)
          catch
            :exit, _ -> :ok
          end
      end
    end

    Process.sleep(10)
  end

  defp safe_call(name, fun) do
    case Process.whereis(name) do
      nil -> :ok
      _pid ->
        try do
          apply(name, fun, [])
        catch
          :exit, _ -> :ok
        end
    end
  end

  describe "call_batch/2 in closed state" do
    test "resets failure count on success and queues batch on failure" do
      # Failures increment count and queue batches
      CircuitBreaker.call_batch([%{reason: "error1"}], fn -> {:error, :fail} end)
      CircuitBreaker.call_batch([%{reason: "error2"}], fn -> {:error, :fail} end)

      assert CircuitBreaker.state().failure_count == 2
      assert CircuitBreaker.state().state == :closed
      assert Storage.queue_size() == 2

      # Success resets failure count
      result = CircuitBreaker.call_batch([%{}], fn -> {:ok, :success} end)

      assert result == {:ok, :success}
      assert CircuitBreaker.state().failure_count == 0
    end
  end

  describe "circuit opening" do
    test "opens circuit after threshold failures" do
      CircuitBreaker.call_batch([%{}], fn -> {:error, :fail1} end)
      CircuitBreaker.call_batch([%{}], fn -> {:error, :fail2} end)

      assert CircuitBreaker.state().state == :closed

      CircuitBreaker.call_batch([%{}], fn -> {:error, :fail3} end)

      assert CircuitBreaker.state().state == :open
      assert CircuitBreaker.state().failure_count == 3
    end
  end

  describe "call_batch/2 in open state" do
    setup do
      for _ <- 1..3 do
        CircuitBreaker.call_batch([%{}], fn -> {:error, :fail} end)
      end

      assert CircuitBreaker.state().state == :open
      :ok
    end

    test "returns dropped when queue is full" do
      for _ <- 1..7 do
        CircuitBreaker.call_batch([%{}], fn -> {:ok, :noop} end)
      end

      result = CircuitBreaker.call_batch([%{}], fn -> {:ok, :noop} end)

      assert result == {:dropped, :queue_full}
    end
  end

  describe "reset/0" do
    test "resets circuit to closed state and cancels recovery timer" do
      for _ <- 1..3 do
        CircuitBreaker.call_batch([%{}], fn -> {:error, :fail} end)
      end

      assert CircuitBreaker.state().state == :open

      assert :ok = CircuitBreaker.reset()

      state = CircuitBreaker.state()
      assert state.state == :closed
      assert state.failure_count == 0
    end
  end

  describe "event filtering" do
    test "filters Tower.ReportEventError and DB connection errors from batch" do
      errors = [
        %Tower.ReportEventError{reporter: TowerDB.Reporter},
        %DBConnection.ConnectionError{message: "connection refused"},
        %Postgrex.Error{postgres: %{code: :connection_failure}},
        %RuntimeError{message: "app error"}
      ]

      # Send batch with all errors
      batch = Enum.map(errors, fn error -> %{reason: error} end)
      CircuitBreaker.call_batch(batch, fn -> {:error, :fail} end)

      # Only the RuntimeError should be queued (filtered batch has 1 event)
      assert Storage.queue_size() == 1

      {:ok, [queued_event]} = Storage.dequeue()
      assert %RuntimeError{} = queued_event.reason
    end
  end

  describe "state/0" do
    test "returns current state info with queue size" do
      CircuitBreaker.call_batch([%{reason: "test1"}], fn -> {:error, :fail} end)
      CircuitBreaker.call_batch([%{reason: "test2"}], fn -> {:error, :fail} end)

      state = CircuitBreaker.state()

      assert state.state == :closed
      assert state.failure_count == 2
      assert state.queue_size == 2
    end
  end
end
