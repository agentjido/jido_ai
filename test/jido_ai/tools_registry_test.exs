defmodule Jido.AI.Tools.RegistryTest do
  use ExUnit.Case, async: false

  alias Jido.AI.ToolAdapter
  alias Jido.AI.Tools.Registry

  # Define test action modules
  defmodule TestActions.Calculator do
    use Jido.Action,
      name: "calculator",
      description: "Performs arithmetic calculations",
      schema: [
        operation: [type: :string, required: true, doc: "The operation to perform"],
        a: [type: :integer, required: true, doc: "First operand"],
        b: [type: :integer, required: true, doc: "Second operand"]
      ]

    @impl true
    def run(_params, _context), do: {:ok, %{}}
  end

  defmodule TestActions.Search do
    use Jido.Action,
      name: "search",
      description: "Searches for information",
      schema: [
        query: [type: :string, required: true, doc: "Search query"]
      ]

    @impl true
    def run(_params, _context), do: {:ok, %{}}
  end

  defmodule TestActions.Weather do
    use Jido.Action,
      name: "weather",
      description: "Gets weather information",
      schema: [
        city: [type: :string, required: true, doc: "City name"]
      ]

    @impl true
    def run(_params, _context), do: {:ok, %{}}
  end

  setup do
    # Clear registry before each test
    Registry.clear()
    :ok
  end

  describe "ToolAdapter.from_actions/2 basic" do
    test "converts single action to tool" do
      [tool] = ToolAdapter.from_actions([TestActions.Calculator])

      assert tool.name == "calculator"
      assert tool.description == "Performs arithmetic calculations"
      assert is_map(tool.parameter_schema)
    end

    test "converts multiple actions to tools" do
      tools =
        ToolAdapter.from_actions([
          TestActions.Calculator,
          TestActions.Search,
          TestActions.Weather
        ])

      assert length(tools) == 3
      names = Enum.map(tools, & &1.name)
      assert "calculator" in names
      assert "search" in names
      assert "weather" in names
    end

    test "returns empty list for empty input" do
      assert ToolAdapter.from_actions([]) == []
    end
  end

  describe "ToolAdapter.from_actions/2 with :prefix option" do
    test "adds prefix to tool names" do
      tools =
        ToolAdapter.from_actions([TestActions.Calculator, TestActions.Search],
          prefix: "myapp_"
        )

      names = Enum.map(tools, & &1.name)
      assert "myapp_calculator" in names
      assert "myapp_search" in names
    end

    test "works with single action" do
      [tool] = ToolAdapter.from_actions([TestActions.Calculator], prefix: "test_")
      assert tool.name == "test_calculator"
    end

    test "nil prefix has no effect" do
      [tool] = ToolAdapter.from_actions([TestActions.Calculator], prefix: nil)
      assert tool.name == "calculator"
    end
  end

  describe "ToolAdapter.from_actions/2 with :filter option" do
    test "filters actions by function" do
      tools =
        ToolAdapter.from_actions(
          [TestActions.Calculator, TestActions.Search, TestActions.Weather],
          filter: fn mod -> mod.name() in ["search", "weather"] end
        )

      assert length(tools) == 2
      names = Enum.map(tools, & &1.name)
      assert "search" in names
      assert "weather" in names
      refute "calculator" in names
    end

    test "filter returning false for all returns empty list" do
      tools =
        ToolAdapter.from_actions([TestActions.Calculator],
          filter: fn _mod -> false end
        )

      assert tools == []
    end

    test "filter returning true for all returns all" do
      tools =
        ToolAdapter.from_actions([TestActions.Calculator, TestActions.Search],
          filter: fn _mod -> true end
        )

      assert length(tools) == 2
    end

    test "nil filter has no effect" do
      tools =
        ToolAdapter.from_actions([TestActions.Calculator, TestActions.Search],
          filter: nil
        )

      assert length(tools) == 2
    end
  end

  describe "ToolAdapter.from_actions/2 with combined options" do
    test "applies both filter and prefix" do
      tools =
        ToolAdapter.from_actions(
          [TestActions.Calculator, TestActions.Search, TestActions.Weather],
          filter: fn mod -> mod.name() in ["search", "weather"] end,
          prefix: "api_"
        )

      assert length(tools) == 2
      names = Enum.map(tools, & &1.name)
      assert "api_search" in names
      assert "api_weather" in names
    end
  end

  describe "ToolAdapter.from_action/2" do
    test "converts single action" do
      tool = ToolAdapter.from_action(TestActions.Calculator)

      assert tool.name == "calculator"
      assert tool.description == "Performs arithmetic calculations"
    end

    test "applies prefix option" do
      tool = ToolAdapter.from_action(TestActions.Calculator, prefix: "v2_")
      assert tool.name == "v2_calculator"
    end
  end

  describe "register_action/1" do
    test "registers action in registry" do
      :ok = Registry.register_action(TestActions.Calculator)

      {:ok, {:action, module}} = Registry.get("calculator")
      assert module == TestActions.Calculator
    end

    test "overwrites existing registration" do
      :ok = Registry.register_action(TestActions.Calculator)
      :ok = Registry.register_action(TestActions.Calculator)

      actions = Registry.list_actions()
      assert length(actions) == 1
    end
  end

  describe "register_actions/1" do
    test "registers multiple actions" do
      :ok =
        Registry.register_actions([
          TestActions.Calculator,
          TestActions.Search
        ])

      actions = Registry.list_actions()
      assert length(actions) == 2
    end
  end

  describe "unregister/1" do
    test "removes action from registry" do
      :ok = Registry.register_action(TestActions.Calculator)
      :ok = Registry.unregister("calculator")

      {:error, :not_found} = Registry.get("calculator")
    end

    test "does nothing for unregistered action" do
      :ok = Registry.unregister("calculator")
      assert Registry.list_actions() == []
    end
  end

  describe "list_actions/0" do
    test "returns empty list when no actions registered" do
      assert Registry.list_actions() == []
    end

    test "returns all registered actions" do
      :ok = Registry.register_actions([TestActions.Calculator, TestActions.Search])

      actions = Registry.list_actions()
      assert length(actions) == 2

      names = Enum.map(actions, fn {name, _mod} -> name end)
      assert "calculator" in names
      assert "search" in names
    end
  end

  describe "get/1" do
    test "returns module for registered action" do
      :ok = Registry.register_action(TestActions.Calculator)

      {:ok, {:action, module}} = Registry.get("calculator")
      assert module == TestActions.Calculator
    end

    test "returns error for unregistered action" do
      {:error, :not_found} = Registry.get("nonexistent")
    end
  end

  describe "clear/0" do
    test "removes all registered actions" do
      :ok =
        Registry.register_actions([
          TestActions.Calculator,
          TestActions.Search,
          TestActions.Weather
        ])

      assert length(Registry.list_actions()) == 3

      :ok = Registry.clear()

      assert Registry.list_actions() == []
    end
  end

  describe "to_reqllm_tools/0" do
    test "converts registered actions to tools" do
      :ok = Registry.register_actions([TestActions.Calculator, TestActions.Search])

      tools = Registry.to_reqllm_tools()

      assert length(tools) == 2
      names = Enum.map(tools, & &1.name)
      assert "calculator" in names
      assert "search" in names
    end

    test "returns empty list when registry is empty" do
      assert Registry.to_reqllm_tools() == []
    end
  end

  describe "ToolAdapter.lookup_action/2" do
    test "finds action by name in list" do
      actions = [TestActions.Calculator, TestActions.Search]

      {:ok, module} = ToolAdapter.lookup_action("calculator", actions)
      assert module == TestActions.Calculator

      {:ok, module} = ToolAdapter.lookup_action("search", actions)
      assert module == TestActions.Search
    end

    test "returns error when not found" do
      actions = [TestActions.Calculator]

      {:error, :not_found} = ToolAdapter.lookup_action("search", actions)
    end

    test "returns error for empty list" do
      {:error, :not_found} = ToolAdapter.lookup_action("calculator", [])
    end
  end
end
