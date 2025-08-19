defmodule JidoTest.Signal.Bus.MiddlewareBehaviorTest do
  use ExUnit.Case, async: true

  alias Jido.Signal
  alias Jido.Signal.Bus.Subscriber

  @moduletag :capture_log

  # Test implementation using the __using__ macro
  defmodule DefaultImplementationTest do
    use Jido.Signal.Bus.Middleware
  end

  # Test implementation with custom overrides
  defmodule CustomImplementationTest do
    use Jido.Signal.Bus.Middleware

    @impl true
    def init(opts) do
      custom_state = Keyword.get(opts, :custom_state, "default")
      {:ok, %{custom: custom_state}}
    end

    @impl true
    def before_publish(signals, _context, state) do
      modified_signals =
        Enum.map(signals, fn signal ->
          %{signal | data: Map.put(signal.data || %{}, :custom_flag, true)}
        end)

      {:cont, modified_signals, state}
    end

    @impl true
    def after_publish(signals, _context, state) do
      updated_state = Map.put(state, :after_publish_called, true)
      {:cont, signals, updated_state}
    end

    @impl true
    def before_dispatch(signal, _subscriber, _context, state) do
      updated_signal = %{signal | data: Map.put(signal.data || %{}, :before_dispatch, true)}
      {:cont, updated_signal, state}
    end

    @impl true
    def after_dispatch(_signal, _subscriber, _result, _context, state) do
      updated_state = Map.put(state, :after_dispatch_called, true)
      {:cont, updated_state}
    end
  end

  # Test implementation that returns errors
  defmodule ErrorImplementationTest do
    use Jido.Signal.Bus.Middleware

    @impl true
    def init(_opts) do
      {:error, :init_failed}
    end
  end

  describe "__using__ macro default implementations" do
    test "init/1 returns default state" do
      assert {:ok, %{}} = DefaultImplementationTest.init([])
      assert {:ok, %{}} = DefaultImplementationTest.init(some: :option)
    end

    test "before_publish/3 returns signals unchanged" do
      signals = [%Signal{id: "test", type: "test", source: "/test"}]
      context = %{bus_name: :test, timestamp: DateTime.utc_now(), metadata: %{}}
      state = %{}

      assert {:cont, ^signals, ^state} =
               DefaultImplementationTest.before_publish(signals, context, state)
    end

    test "after_publish/3 returns signals unchanged" do
      signals = [%Signal{id: "test", type: "test", source: "/test"}]
      context = %{bus_name: :test, timestamp: DateTime.utc_now(), metadata: %{}}
      state = %{}

      assert {:cont, ^signals, ^state} =
               DefaultImplementationTest.after_publish(signals, context, state)
    end

    test "before_dispatch/4 returns signal unchanged" do
      signal = %Signal{id: "test", type: "test", source: "/test"}
      subscriber = %Subscriber{id: "test", path: "test", dispatch: {:pid, self()}}
      context = %{bus_name: :test, timestamp: DateTime.utc_now(), metadata: %{}}
      state = %{}

      assert {:cont, ^signal, ^state} =
               DefaultImplementationTest.before_dispatch(signal, subscriber, context, state)
    end

    test "after_dispatch/5 returns state unchanged" do
      signal = %Signal{id: "test", type: "test", source: "/test"}
      subscriber = %Subscriber{id: "test", path: "test", dispatch: {:pid, self()}}
      result = :ok
      context = %{bus_name: :test, timestamp: DateTime.utc_now(), metadata: %{}}
      state = %{}

      assert {:cont, ^state} =
               DefaultImplementationTest.after_dispatch(
                 signal,
                 subscriber,
                 result,
                 context,
                 state
               )
    end
  end

  describe "custom implementation overrides" do
    test "init/1 can be overridden" do
      assert {:ok, %{custom: "default"}} = CustomImplementationTest.init([])
      assert {:ok, %{custom: "test"}} = CustomImplementationTest.init(custom_state: "test")
    end

    test "before_publish/3 can modify signals" do
      signals = [%Signal{id: "test", type: "test", source: "/test", data: %{original: true}}]
      context = %{bus_name: :test, timestamp: DateTime.utc_now(), metadata: %{}}
      state = %{custom: "test"}

      assert {:cont, modified_signals, ^state} =
               CustomImplementationTest.before_publish(signals, context, state)

      [modified_signal] = modified_signals
      assert modified_signal.data.custom_flag == true
      assert modified_signal.data.original == true
    end

    test "after_publish/3 can modify state" do
      signals = [%Signal{id: "test", type: "test", source: "/test"}]
      context = %{bus_name: :test, timestamp: DateTime.utc_now(), metadata: %{}}
      state = %{custom: "test"}

      assert {:cont, ^signals, updated_state} =
               CustomImplementationTest.after_publish(signals, context, state)

      assert updated_state.after_publish_called == true
      assert updated_state.custom == "test"
    end

    test "before_dispatch/4 can modify signal" do
      signal = %Signal{id: "test", type: "test", source: "/test", data: %{original: true}}
      subscriber = %Subscriber{id: "test", path: "test", dispatch: {:pid, self()}}
      context = %{bus_name: :test, timestamp: DateTime.utc_now(), metadata: %{}}
      state = %{custom: "test"}

      assert {:cont, modified_signal, ^state} =
               CustomImplementationTest.before_dispatch(signal, subscriber, context, state)

      assert modified_signal.data.before_dispatch == true
      assert modified_signal.data.original == true
    end

    test "after_dispatch/5 can modify state" do
      signal = %Signal{id: "test", type: "test", source: "/test"}
      subscriber = %Subscriber{id: "test", path: "test", dispatch: {:pid, self()}}
      result = :ok
      context = %{bus_name: :test, timestamp: DateTime.utc_now(), metadata: %{}}
      state = %{custom: "test"}

      assert {:cont, updated_state} =
               CustomImplementationTest.after_dispatch(signal, subscriber, result, context, state)

      assert updated_state.after_dispatch_called == true
      assert updated_state.custom == "test"
    end
  end

  describe "error handling in implementations" do
    test "init/1 can return errors" do
      assert {:error, :init_failed} = ErrorImplementationTest.init([])
    end
  end

  describe "context structure validation" do
    test "context contains required fields" do
      context = %{
        bus_name: :test_bus,
        timestamp: DateTime.utc_now(),
        metadata: %{custom: "data"}
      }

      signals = [%Signal{id: "test", type: "test", source: "/test"}]
      state = %{}

      # Ensure the context structure is valid for all callbacks
      assert {:cont, ^signals, ^state} =
               DefaultImplementationTest.before_publish(signals, context, state)

      assert {:cont, ^signals, ^state} =
               DefaultImplementationTest.after_publish(signals, context, state)

      signal = List.first(signals)
      subscriber = %Subscriber{id: "test", path: "test", dispatch: {:pid, self()}}

      assert {:cont, ^signal, ^state} =
               DefaultImplementationTest.before_dispatch(signal, subscriber, context, state)

      assert {:cont, ^state} =
               DefaultImplementationTest.after_dispatch(signal, subscriber, :ok, context, state)
    end
  end

  describe "dispatch result types" do
    test "after_dispatch handles :ok result" do
      signal = %Signal{id: "test", type: "test", source: "/test"}
      subscriber = %Subscriber{id: "test", path: "test", dispatch: {:pid, self()}}
      context = %{bus_name: :test, timestamp: DateTime.utc_now(), metadata: %{}}
      state = %{}

      assert {:cont, ^state} =
               DefaultImplementationTest.after_dispatch(signal, subscriber, :ok, context, state)
    end

    test "after_dispatch handles error result" do
      signal = %Signal{id: "test", type: "test", source: "/test"}
      subscriber = %Subscriber{id: "test", path: "test", dispatch: {:pid, self()}}
      context = %{bus_name: :test, timestamp: DateTime.utc_now(), metadata: %{}}
      state = %{}

      error_result = {:error, :dispatch_failed}

      assert {:cont, ^state} =
               DefaultImplementationTest.after_dispatch(
                 signal,
                 subscriber,
                 error_result,
                 context,
                 state
               )
    end
  end

  describe "type specifications" do
    test "modules using middleware have correct behaviour" do
      # Verify the behaviour is properly attached
      assert DefaultImplementationTest.__info__(:attributes)[:behaviour] == [
               Jido.Signal.Bus.Middleware
             ]

      assert CustomImplementationTest.__info__(:attributes)[:behaviour] == [
               Jido.Signal.Bus.Middleware
             ]
    end
  end
end
