defmodule TowerDB.CircuitBreakerTest do
  use ExUnit.Case, async: false

  alias TowerDB.CircuitBreaker
  alias TowerDB.CircuitBreaker.Storage

  setup do
    # Configure short timeouts for faster tests
    Application.put_env(:tower_db, :circuit_breaker,
      failure_threshold: 3,
      recovery_timeout: 50,
      queue_retry_interval: 10,
      max_queue_size: 10
    )

    # Stop the application supervisor to prevent it from restarting processes
    case Process.whereis(TowerDB.Supervisor) do
      nil -> :ok
      pid -> Supervisor.stop(pid)
    end

    # Start fresh
    {:ok, _} = Storage.start_link()
    {:ok, _} = CircuitBreaker.start_link()

    on_exit(fn ->
      Application.delete_env(:tower_db, :circuit_breaker)

      case Process.whereis(CircuitBreaker) do
        nil -> :ok
        pid -> GenServer.stop(pid)
      end
    end)

    :ok
  end

  describe "call/2 in closed state" do
    test "resets failure count on success and queues events on failure" do
      # Failures increment count and queue events
      CircuitBreaker.call(%{reason: "error1"}, fn -> {:error, :fail} end)
      CircuitBreaker.call(%{reason: "error2"}, fn -> {:error, :fail} end)

      assert CircuitBreaker.state().failure_count == 2
      assert CircuitBreaker.state().state == :closed
      assert Storage.queue_size() == 2

      # Success resets failure count
      result = CircuitBreaker.call(%{}, fn -> {:ok, :success} end)

      assert result == {:ok, :success}
      assert CircuitBreaker.state().failure_count == 0
    end
  end

  describe "circuit opening" do
    test "opens circuit after threshold failures" do
      CircuitBreaker.call(%{}, fn -> {:error, :fail1} end)
      CircuitBreaker.call(%{}, fn -> {:error, :fail2} end)

      assert CircuitBreaker.state().state == :closed

      CircuitBreaker.call(%{}, fn -> {:error, :fail3} end)

      assert CircuitBreaker.state().state == :open
      assert CircuitBreaker.state().failure_count == 3
    end
  end

  describe "call/2 in open state" do
    setup do
      for _ <- 1..3 do
        CircuitBreaker.call(%{}, fn -> {:error, :fail} end)
      end

      assert CircuitBreaker.state().state == :open
      :ok
    end

    test "returns dropped when queue is full" do
      # Fill the queue (max is 10, we have 3 from setup)
      for _ <- 1..7 do
        CircuitBreaker.call(%{}, fn -> {:ok, :noop} end)
      end

      result = CircuitBreaker.call(%{}, fn -> {:ok, :noop} end)

      assert result == {:dropped, :queue_full}
    end
  end

  describe "reset/0" do
    test "resets circuit to closed state and cancels recovery timer" do
      for _ <- 1..3 do
        CircuitBreaker.call(%{}, fn -> {:error, :fail} end)
      end

      assert CircuitBreaker.state().state == :open

      assert :ok = CircuitBreaker.reset()

      state = CircuitBreaker.state()
      assert state.state == :closed
      assert state.failure_count == 0
    end
  end

  describe "event filtering" do
    test "filters Tower.ReportEventError and DB connection errors" do
      errors = [
        %Tower.ReportEventError{reporter: TowerDB.Reporter},
        %DBConnection.ConnectionError{message: "connection refused"},
        %Postgrex.Error{postgres: %{code: :connection_failure}},
        %RuntimeError{message: "app error"}
      ]

      for error <- errors do
        CircuitBreaker.call(%{reason: error}, fn -> {:error, :fail} end)
      end

      assert Storage.queue_size() == 1
    end
  end

  describe "state/0" do
    test "returns current state info with queue size" do
      CircuitBreaker.call(%{reason: "test1"}, fn -> {:error, :fail} end)
      CircuitBreaker.call(%{reason: "test2"}, fn -> {:error, :fail} end)

      state = CircuitBreaker.state()

      assert state.state == :closed
      assert state.failure_count == 2
      assert state.queue_size == 2
    end
  end
end
