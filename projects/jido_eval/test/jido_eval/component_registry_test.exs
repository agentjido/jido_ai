defmodule Jido.Eval.ComponentRegistryTest do
  # ETS table is shared
  use ExUnit.Case, async: false

  alias Jido.Eval.ComponentRegistry

  # Test implementations
  defmodule TestReporter do
    @behaviour Jido.Eval.Reporter
    def handle_summary(_summary, _opts), do: :ok
  end

  defmodule TestStore do
    @behaviour Jido.Eval.Store
    def init(_opts), do: {:ok, %{}}
    def persist(_data, state), do: {:ok, state}
    def finalize(_state), do: :ok
  end

  defmodule TestBroadcaster do
    @behaviour Jido.Eval.Broadcaster
    def publish(_event, _data, _opts), do: :ok
  end

  defmodule TestProcessor do
    @behaviour Jido.Eval.Processor
    def process(data, _stage, _opts), do: {:ok, data}
  end

  defmodule TestMiddleware do
    @behaviour Jido.Eval.Middleware
    def call(metric_fn, _context, _opts), do: metric_fn.()
  end

  defmodule TestMetric do
    @behaviour Jido.Eval.Metric
    def name, do: "Test Metric"
    def description, do: "A test metric"
    def required_fields, do: [:response]
    def sample_types, do: [:single_turn]
    def score_range, do: {0.0, 1.0}
    def evaluate(_sample, _config, _opts), do: {:ok, 0.5}
  end

  defmodule InvalidModule do
    # Does not implement any behaviour
  end

  setup do
    ComponentRegistry.start_link()
    ComponentRegistry.clear()
    :ok
  end

  describe "start_link/0" do
    test "starts registry successfully" do
      assert ComponentRegistry.start_link() == :ok
    end

    test "returns ok if already started" do
      ComponentRegistry.start_link()
      assert ComponentRegistry.start_link() == :ok
    end
  end

  describe "register/2" do
    test "registers valid reporter" do
      assert ComponentRegistry.register(:reporter, TestReporter) == :ok
    end

    test "registers valid store" do
      assert ComponentRegistry.register(:store, TestStore) == :ok
    end

    test "registers valid broadcaster" do
      assert ComponentRegistry.register(:broadcaster, TestBroadcaster) == :ok
    end

    test "registers valid processor" do
      assert ComponentRegistry.register(:processor, TestProcessor) == :ok
    end

    test "registers valid middleware" do
      assert ComponentRegistry.register(:middleware, TestMiddleware) == :ok
    end

    test "registers valid metric" do
      assert ComponentRegistry.register(:metric, TestMetric) == :ok
    end

    test "rejects invalid component type" do
      assert {:error, {:invalid_type, :invalid}} =
               ComponentRegistry.register(:invalid, TestReporter)
    end

    test "rejects module without required behaviour" do
      assert {:error, {:missing_behaviour, Jido.Eval.Reporter}} =
               ComponentRegistry.register(:reporter, InvalidModule)
    end

    test "rejects metric without required behaviour" do
      assert {:error, {:missing_behaviour, Jido.Eval.Metric}} =
               ComponentRegistry.register(:metric, InvalidModule)
    end

    test "rejects non-existent module" do
      assert {:error, {:module_load_error, :nofile}} =
               ComponentRegistry.register(:reporter, NonExistentModule)
    end
  end

  describe "lookup/2" do
    test "finds registered component" do
      ComponentRegistry.register(:reporter, TestReporter)

      assert {:ok, TestReporter} =
               ComponentRegistry.lookup(:reporter, TestReporter)
    end

    test "returns not found for unregistered component" do
      assert {:error, :not_found} =
               ComponentRegistry.lookup(:reporter, UnknownReporter)
    end

    test "returns not found for wrong type" do
      ComponentRegistry.register(:reporter, TestReporter)

      assert {:error, :not_found} =
               ComponentRegistry.lookup(:store, TestReporter)
    end
  end

  describe "list/1" do
    test "returns empty list when no components registered" do
      assert ComponentRegistry.list(:reporter) == []
    end

    test "returns list of registered components" do
      ComponentRegistry.register(:reporter, TestReporter)

      assert ComponentRegistry.list(:reporter) == [TestReporter]
    end

    test "returns components for specific type only" do
      ComponentRegistry.register(:reporter, TestReporter)
      ComponentRegistry.register(:store, TestStore)

      assert ComponentRegistry.list(:reporter) == [TestReporter]
      assert ComponentRegistry.list(:store) == [TestStore]
    end

    test "handles multiple components of same type" do
      defmodule AnotherTestReporter do
        @behaviour Jido.Eval.Reporter
        def handle_summary(_summary, _opts), do: :ok
      end

      ComponentRegistry.register(:reporter, TestReporter)
      ComponentRegistry.register(:reporter, AnotherTestReporter)

      reporters = ComponentRegistry.list(:reporter)
      assert length(reporters) == 2
      assert TestReporter in reporters
      assert AnotherTestReporter in reporters
    end
  end

  describe "clear/0" do
    test "clears all registered components" do
      ComponentRegistry.register(:reporter, TestReporter)
      ComponentRegistry.register(:store, TestStore)

      assert ComponentRegistry.list(:reporter) == [TestReporter]
      assert ComponentRegistry.list(:store) == [TestStore]

      ComponentRegistry.clear()

      assert ComponentRegistry.list(:reporter) == []
      assert ComponentRegistry.list(:store) == []
    end
  end

  describe "integration" do
    test "complete workflow with all component types" do
      # Register all types
      assert ComponentRegistry.register(:reporter, TestReporter) == :ok
      assert ComponentRegistry.register(:store, TestStore) == :ok
      assert ComponentRegistry.register(:broadcaster, TestBroadcaster) == :ok
      assert ComponentRegistry.register(:processor, TestProcessor) == :ok
      assert ComponentRegistry.register(:middleware, TestMiddleware) == :ok

      # Verify all are registered
      assert {:ok, TestReporter} = ComponentRegistry.lookup(:reporter, TestReporter)
      assert {:ok, TestStore} = ComponentRegistry.lookup(:store, TestStore)
      assert {:ok, TestBroadcaster} = ComponentRegistry.lookup(:broadcaster, TestBroadcaster)
      assert {:ok, TestProcessor} = ComponentRegistry.lookup(:processor, TestProcessor)
      assert {:ok, TestMiddleware} = ComponentRegistry.lookup(:middleware, TestMiddleware)

      # Verify lists
      assert ComponentRegistry.list(:reporter) == [TestReporter]
      assert ComponentRegistry.list(:store) == [TestStore]
      assert ComponentRegistry.list(:broadcaster) == [TestBroadcaster]
      assert ComponentRegistry.list(:processor) == [TestProcessor]
      assert ComponentRegistry.list(:middleware) == [TestMiddleware]
    end
  end
end
