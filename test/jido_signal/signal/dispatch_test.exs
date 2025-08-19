defmodule Jido.Signal.DispatchTest do
  use ExUnit.Case, async: true

  alias Jido.Signal.Dispatch

  setup do
    # Enable error normalization for all tests
    Application.put_env(:jido, :normalize_dispatch_errors, true)

    on_exit(fn ->
      # Reset to default after tests
      Application.delete_env(:jido, :normalize_dispatch_errors)
    end)

    :ok
  end

  # Mock bus adapter for testing
  defmodule MockBusAdapter do
    @behaviour Jido.Signal.Dispatch.Adapter

    def validate_opts(opts) do
      if Keyword.has_key?(opts, :target) and Keyword.has_key?(opts, :stream) do
        {:ok, opts}
      else
        {:error, :invalid_bus_config}
      end
    end

    def deliver(_signal, _opts), do: :ok
  end

  # Test adapter for batch testing
  defmodule TestBatchAdapter do
    @behaviour Jido.Signal.Dispatch.Adapter

    def validate_opts(opts) do
      if Keyword.has_key?(opts, :target) do
        {:ok, opts}
      else
        {:error, :invalid_config}
      end
    end

    def deliver(signal, opts) do
      send(opts[:target], {:batch_signal, signal, opts[:index]})
      :ok
    end
  end

  describe "pid adapter" do
    setup do
      signal = %Jido.Signal{
        id: "test_signal",
        type: "test",
        source: "test",
        time: DateTime.utc_now(),
        data: %{}
      }

      {:ok, signal: signal}
    end

    test "delivers signal asynchronously to pid", %{signal: signal} do
      config = {:pid, [target: self(), delivery_mode: :async]}
      assert :ok = Dispatch.dispatch(signal, config)
      assert_receive {:signal, ^signal}
    end

    test "delivers signal synchronously to pid", %{signal: signal} do
      me = self()

      # Start a process that will respond to sync messages
      pid =
        spawn(fn ->
          receive do
            {:"$gen_call", from, {:signal, signal}} ->
              GenServer.reply(from, :ok)
              send(me, {:received, signal})
          end
        end)

      config = {:pid, [target: pid, delivery_mode: :sync]}
      assert :ok = Dispatch.dispatch(signal, config)
      assert_receive {:received, ^signal}
    end

    test "returns error when target process is not alive", %{signal: signal} do
      pid = spawn(fn -> :ok end)
      # Ensure process is dead
      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, _}

      config = {:pid, [target: pid, delivery_mode: :async]}
      assert {:error, %Jido.Signal.Error.DispatchError{}} = Dispatch.dispatch(signal, config)
    end
  end

  describe "named adapter" do
    setup do
      signal = %Jido.Signal{
        id: "test_signal",
        type: "test",
        source: "test",
        time: DateTime.utc_now(),
        data: %{}
      }

      {:ok, signal: signal}
    end

    test "delivers signal asynchronously to named process", %{signal: signal} do
      name = :test_named_process
      Process.register(self(), name)

      config = {:named, [target: {:name, name}, delivery_mode: :async]}
      assert :ok = Dispatch.dispatch(signal, config)
      assert_receive {:signal, ^signal}
    end

    test "returns error when named process not found", %{signal: signal} do
      config = {:named, [target: {:name, :nonexistent_process}, delivery_mode: :async]}
      assert {:error, %Jido.Signal.Error.DispatchError{}} = Dispatch.dispatch(signal, config)
    end
  end

  describe "bus adapter" do
    setup do
      signal = %Jido.Signal{
        id: "test_signal",
        type: "test",
        source: "test",
        time: DateTime.utc_now(),
        data: %{}
      }

      {:ok, signal: signal}
    end

    test "delivers signal to bus", %{signal: signal} do
      config = {MockBusAdapter, [target: :test_bus, stream: "test_stream"]}
      assert :ok = Dispatch.dispatch(signal, config)
    end

    test "returns error when bus config is invalid", %{signal: signal} do
      # Missing stream
      config = {MockBusAdapter, [target: :test_bus]}
      assert {:error, %Jido.Signal.Error.DispatchError{}} = Dispatch.dispatch(signal, config)
    end
  end

  describe "validate_opts/1" do
    test "validates pid adapter configuration" do
      config = {:pid, [target: self(), delivery_mode: :async]}
      assert {:ok, {adapter, opts}} = Dispatch.validate_opts(config)
      assert adapter == :pid
      assert Keyword.get(opts, :target) == self()
      assert Keyword.get(opts, :delivery_mode) == :async
    end

    test "validates bus adapter configuration" do
      config = {MockBusAdapter, [target: :test_bus, stream: "test_stream"]}
      assert {:ok, {adapter, opts}} = Dispatch.validate_opts(config)
      assert adapter == MockBusAdapter
      assert Keyword.get(opts, :target) == :test_bus
      assert Keyword.get(opts, :stream) == "test_stream"
    end

    test "validates named adapter configuration" do
      config = {:named, [target: {:name, :test_process}, delivery_mode: :async]}
      assert {:ok, {adapter, opts}} = Dispatch.validate_opts(config)
      assert adapter == :named
      assert Keyword.get(opts, :target) == {:name, :test_process}
      assert Keyword.get(opts, :delivery_mode) == :async
    end

    test "returns error for invalid adapter" do
      config = {:invalid_adapter, []}
      assert {:error, _} = Dispatch.validate_opts(config)
    end

    test "validates multiple dispatch configurations with default" do
      config = [
        {MockBusAdapter, [target: :test_bus, stream: "events"]},
        {:pid, [target: self(), delivery_mode: :async]}
      ]

      assert {:ok, validated_config} = Dispatch.validate_opts(config)
      assert length(validated_config) == 2
      assert Enum.all?(validated_config, fn conf -> match?({_adapter, _opts}, conf) end)
    end

    test "returns error when any dispatcher in the list is invalid" do
      config = [
        {MockBusAdapter, [target: :test_bus, stream: "events"]},
        {:invalid_adapter, []}
      ]

      assert {:error, _} = Dispatch.validate_opts(config)
    end
  end

  describe "multiple dispatch" do
    setup do
      signal = %Jido.Signal{
        id: "test_signal",
        type: "test.event",
        source: "test",
        time: DateTime.utc_now(),
        data: %{value: 42}
      }

      # Create a named process to receive signals
      named_process = :"test_process_#{:erlang.unique_integer()}"
      test_pid = self()

      _named_pid =
        spawn(fn ->
          Process.register(self(), named_process)

          # Keep receiving signals until test is done
          receive_loop = fn receive_loop ->
            receive do
              {:signal, signal} ->
                send(test_pid, {:named_received, signal})
                receive_loop.(receive_loop)
            end
          end

          receive_loop.(receive_loop)
        end)

      # Give the process time to register
      Process.sleep(10)

      {:ok, signal: signal, named_process: named_process}
    end

    @tag :capture_log
    test "delivers signal to multiple adapters simultaneously", %{
      signal: signal,
      named_process: named_process
    } do
      test_pid = self()

      # Configure multiple adapters:
      # - PID adapter for direct process delivery
      # - Named adapter for named process delivery
      # - Logger adapter for logging
      config = [
        {:pid, [target: test_pid, delivery_mode: :async]},
        {:named, [target: {:name, named_process}, delivery_mode: :async]},
        {:logger, [level: :debug]}
      ]

      assert :ok = Dispatch.dispatch(signal, config)

      # Verify signal received via PID adapter
      assert_receive {:signal, received_signal}
      assert received_signal.id == signal.id
      assert received_signal.data.value == 42

      # Verify signal received via Named adapter
      assert_receive {:named_received, named_signal}
      assert named_signal.id == signal.id
      assert named_signal.data.value == 42
    end

    @tag :capture_log
    test "handles mix of sync and async dispatch modes", %{signal: signal} do
      test_pid = self()

      config = [
        {:pid, [target: test_pid, delivery_mode: :sync]},
        {:pid, [target: test_pid, delivery_mode: :async]},
        {:logger, [level: :debug]}
      ]

      assert {:error, %Jido.Signal.Error.DispatchError{}} = Dispatch.dispatch(signal, config)

      # Should still receive the async signal
      assert_receive {:signal, received_signal}
      assert received_signal.id == signal.id
    end

    @tag :capture_log
    test "returns error if any dispatcher fails but completes successful dispatches", %{
      signal: signal
    } do
      test_pid = self()
      dead_pid = spawn(fn -> :ok end)
      ref = Process.monitor(dead_pid)
      assert_receive {:DOWN, ^ref, :process, ^dead_pid, _}

      config = [
        {:pid, [target: test_pid, delivery_mode: :async]},
        {:pid, [target: dead_pid, delivery_mode: :async]},
        {:logger, [level: :debug]}
      ]

      assert {:error, %Jido.Signal.Error.DispatchError{}} = Dispatch.dispatch(signal, config)

      # Verify successful dispatches still occurred
      assert_receive {:signal, received_signal}
      assert received_signal.id == signal.id
    end
  end

  describe "dispatch_async/2" do
    setup do
      signal = %Jido.Signal{
        id: "test_signal",
        type: "test",
        source: "test",
        time: DateTime.utc_now(),
        data: %{}
      }

      {:ok, signal: signal}
    end

    test "returns task reference immediately", %{signal: signal} do
      config = {:pid, [target: self(), delivery_mode: :async]}
      assert {:ok, task} = Dispatch.dispatch_async(signal, config)
      assert is_pid(task.pid)

      # Wait for completion
      assert :ok = Task.await(task)
      assert_receive {:signal, ^signal}
    end

    test "handles errors in async dispatch", %{signal: signal} do
      pid = spawn(fn -> :ok end)
      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, _}

      config = {:pid, [target: pid, delivery_mode: :async]}
      assert {:ok, task} = Dispatch.dispatch_async(signal, config)

      assert {:error, %Jido.Signal.Error.DispatchError{}} = Task.await(task)
    end

    test "supports multiple async dispatches", %{signal: signal} do
      test_pid = self()

      configs = [
        {:pid, [target: test_pid, delivery_mode: :async]},
        {:pid, [target: test_pid, delivery_mode: :async]},
        {:logger, [level: :debug]}
      ]

      assert {:ok, task} = Dispatch.dispatch_async(signal, configs)
      assert :ok = Task.await(task)

      # Should receive two signals
      assert_receive {:signal, ^signal}
      assert_receive {:signal, ^signal}
    end
  end

  describe "dispatch_batch/3" do
    setup do
      signal = %Jido.Signal{
        id: "test_signal",
        type: "test",
        source: "test",
        time: DateTime.utc_now(),
        data: %{}
      }

      test_pid = self()

      # Create test configs that will report back to test process
      configs =
        for i <- 1..100 do
          {TestBatchAdapter, [target: test_pid, index: i]}
        end

      {:ok, signal: signal, configs: configs}
    end

    test "dispatches in batches with default options", %{signal: signal, configs: configs} do
      assert :ok = Dispatch.dispatch_batch(signal, configs, [])

      # Collect all signals and verify order
      signals =
        for _ <- 1..100 do
          receive do
            {:batch_signal, ^signal, idx} -> idx
          after
            1000 -> flunk("Timeout waiting for signal")
          end
        end
        |> Enum.sort()

      assert signals == Enum.to_list(1..100)
    end

    test "respects batch size option", %{signal: signal, configs: configs} do
      batch_size = 10
      test_pid = self()

      # Track batch arrival times
      arrival_tracker = :ets.new(:arrival_tracker, [:set, :public])

      spawn_link(fn ->
        assert :ok = Dispatch.dispatch_batch(signal, configs, batch_size: batch_size)
        send(test_pid, :done)
      end)

      # Collect signals and track batch timing
      signals =
        for _ <- 1..100 do
          receive do
            {:batch_signal, ^signal, idx} ->
              batch_num = div(idx - 1, batch_size)
              now = System.monotonic_time(:millisecond)
              :ets.insert(arrival_tracker, {batch_num, now})
              idx
          after
            1000 -> flunk("Timeout waiting for signal")
          end
        end
        |> Enum.sort()

      assert_receive :done

      # Analyze batch timing
      batch_times = :ets.tab2list(arrival_tracker)
      :ets.delete(arrival_tracker)

      # Verify all signals received in order
      assert signals == Enum.to_list(1..100)

      # Verify batching occurred
      batch_count =
        batch_times
        |> Enum.map(&elem(&1, 0))
        |> Enum.uniq()
        |> length()

      assert batch_count == div(100, batch_size),
             "Expected #{div(100, batch_size)} batches, got #{batch_count}"
    end

    test "handles errors in batches", %{signal: signal} do
      test_pid = self()

      # Mix of valid and invalid configs
      configs = [
        {TestBatchAdapter, [target: test_pid, index: 1]},
        # Invalid config
        {TestBatchAdapter, []},
        {TestBatchAdapter, [target: test_pid, index: 3]}
      ]

      assert {:error, [{1, %Jido.Signal.Error.InvalidInputError{}}]} =
               Dispatch.dispatch_batch(signal, configs, [])

      # Should still receive signals from successful dispatches
      assert_receive {:batch_signal, ^signal, 1}
      assert_receive {:batch_signal, ^signal, 3}
      refute_receive {:batch_signal, ^signal, 2}
    end

    test "supports custom batch concurrency", %{signal: signal, configs: configs} do
      batch_size = 10
      max_concurrency = 2
      test_pid = self()

      # Track concurrent processing
      concurrency_tracker = :ets.new(:concurrency_tracker, [:set, :public])

      # Track active batches
      active_batches = :ets.new(:active_batches, [:set, :public])
      :ets.insert(active_batches, {:count, 0})

      spawn_link(fn ->
        assert :ok =
                 Dispatch.dispatch_batch(signal, configs,
                   batch_size: batch_size,
                   max_concurrency: max_concurrency
                 )

        send(test_pid, :done)
      end)

      # Helper to track concurrency
      track_batch = fn idx ->
        batch_num = div(idx - 1, batch_size)
        [{:count, count}] = :ets.lookup(active_batches, :count)
        new_count = count + 1
        :ets.insert(active_batches, {:count, new_count})
        :ets.insert(concurrency_tracker, {batch_num, new_count})
        # Simulate work
        Process.sleep(10)
        :ets.insert(active_batches, {:count, count})
      end

      # Collect signals and track concurrency
      signals =
        for _ <- 1..100 do
          receive do
            {:batch_signal, ^signal, idx} ->
              track_batch.(idx)
              idx
          after
            1000 -> flunk("Timeout waiting for signal")
          end
        end
        |> Enum.sort()

      assert_receive :done

      # Analyze concurrency
      concurrency_levels =
        concurrency_tracker
        |> :ets.tab2list()
        |> Enum.map(&elem(&1, 1))

      :ets.delete(concurrency_tracker)
      :ets.delete(active_batches)

      # Verify all signals received in order
      assert signals == Enum.to_list(1..100)

      # Verify concurrency was respected
      max_concurrent = Enum.max(concurrency_levels)

      assert max_concurrent <= max_concurrency,
             "Max concurrency exceeded: got #{max_concurrent} concurrent batches"
    end
  end
end
