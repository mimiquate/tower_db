defmodule TowerDB.BufferTest do
  use ExUnit.Case, async: false

  alias TowerDB.Buffer
  alias TowerDB.CircuitBreaker
  alias TowerDB.CircuitBreaker.Storage

  @processes [Buffer, CircuitBreaker, Storage]

  setup do
    stop_supervisor()
    stop_processes(@processes)

    {:ok, _} = Storage.start_link()
    {:ok, _} = CircuitBreaker.start_link()
    {:ok, _} = Buffer.start_link()

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

  describe "add/1" do
    test "flushes when batch_size is reached" do
      for i <- 1..5 do
        Buffer.add(%{reason: "error #{i}", kind: :error})
      end

      Process.sleep(10)

      state = Buffer.state()

      assert state.total_received == 5
      assert state.total_flushed == 5
      assert state.buffer_size == 0
    end

    test "flushes after interval when batch_size not reached" do
      for i <- 1..3 do
        Buffer.add(%{reason: "error #{i}", kind: :error})
      end

      Process.sleep(10)
      state = Buffer.state()

      assert state.total_received == 3
      assert state.buffer_size == 3
      assert state.total_flushed == 0

      Process.sleep(120)

      state = Buffer.state()

      assert state.total_received == 3
      assert state.buffer_size == 0
      assert state.total_flushed == 3
    end

    test "holds events when circuit breaker queue is full" do
      for _ <- 1..3 do
        CircuitBreaker.call_batch([%{}], fn -> {:error, :fail} end)
      end

      Process.sleep(20)
      assert CircuitBreaker.state().state == :open

      for _ <- 1..7 do
        CircuitBreaker.call_batch([%{}], fn -> {:ok, :noop} end)
      end

      Process.sleep(50)
      cb_state = CircuitBreaker.state()
      assert cb_state.state == :open
      assert cb_state.queue_size == 10
      assert CircuitBreaker.can_accept?() == false

      for i <- 1..5 do
        Buffer.add(%{reason: "error #{i}", kind: :error})
      end

      Process.sleep(50)

      state = Buffer.state()

      # Events are held in buffer because circuit can't accept
      assert state.total_received == 5
      assert state.buffer_size == 5
      assert state.total_flushed == 0
    end

    test "retries flush after circuit breaker becomes ready" do
      # Open the circuit by causing failures
      for _ <- 1..3 do
        CircuitBreaker.call_batch([%{}], fn -> {:error, :fail} end)
      end

      Process.sleep(50)
      assert CircuitBreaker.state().state == :open

      # Fill the queue
      for _ <- 1..7 do
        CircuitBreaker.call_batch([%{}], fn -> {:ok, :noop} end)
      end

      Process.sleep(50)
      cb_state = CircuitBreaker.state()
      assert cb_state.state == :open
      assert cb_state.queue_size == 10

      # Add events to buffer - will be held
      for i <- 1..5 do
        Buffer.add(%{reason: "error #{i}", kind: :error})
      end

      Process.sleep(10)

      state = Buffer.state()
      assert state.buffer_size == 5
      assert state.total_flushed == 0

      # Reset circuit breaker - makes it ready again
      CircuitBreaker.reset()

      assert CircuitBreaker.state().state == :closed
      assert CircuitBreaker.can_accept?() == true

      # Wait for backpressure_retry (50ms in test config)
      Process.sleep(80)

      state = Buffer.state()

      # Events should now be flushed
      assert state.total_flushed == 5
      assert state.buffer_size == 0
    end

    test "filters DB-related errors and doesn't add them to buffer" do
      Buffer.add(%{reason: %Tower.ReportEventError{reporter: TowerDB.Reporter}})
      Buffer.add(%{reason: %DBConnection.ConnectionError{message: "connection refused"}})
      Buffer.add(%{reason: %Postgrex.Error{postgres: %{code: :connection_failure}}})
      Buffer.add(%{reason: %RuntimeError{message: "app error"}})

      Process.sleep(10)

      state = Buffer.state()

      assert state.total_received == 1
      assert state.buffer_size == 1
    end
  end
end
