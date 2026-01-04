defmodule Jido.AI.Tools.RegistryTest do
  use ExUnit.Case, async: false

  alias Jido.AI.Tools.Registry

  # Define test Action modules
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

  # Define test Tool modules
  defmodule TestTools.Echo do
    use Jido.AI.Tools.Tool,
      name: "echo",
      description: "Echoes back the input message"

    @impl true
    def schema do
      [
        message: [type: :string, required: true, doc: "Message to echo"]
      ]
    end

    @impl true
    def run(params, _context) do
      {:ok, %{message: params.message}}
    end
  end

  defmodule TestTools.Weather do
    use Jido.AI.Tools.Tool,
      name: "weather",
      description: "Gets weather information"

    @impl true
    def schema do
      [
        city: [type: :string, required: true, doc: "City name"]
      ]
    end

    @impl true
    def run(params, _context) do
      {:ok, %{city: params.city, temp: 72}}
    end
  end

  # A module that doesn't implement any behavior
  defmodule InvalidModule do
    def hello, do: "world"
  end

  setup do
    # Ensure registry is started and clear before each test
    Registry.ensure_started()
    Registry.clear()
    :ok
  end

  describe "register_action/1" do
    test "registers a valid action module" do
      assert :ok = Registry.register_action(TestActions.Calculator)
    end

    test "stores action with correct type" do
      :ok = Registry.register_action(TestActions.Calculator)

      assert {:ok, {:action, TestActions.Calculator}} = Registry.get("calculator")
    end

    test "returns error for non-action module" do
      assert {:error, :not_an_action} = Registry.register_action(InvalidModule)
    end

    test "returns error for tool module" do
      # Tools should not be registered via register_action
      assert {:error, :not_an_action} = Registry.register_action(TestTools.Echo)
    end
  end

  describe "register_actions/1" do
    test "registers multiple action modules" do
      assert :ok = Registry.register_actions([TestActions.Calculator, TestActions.Search])

      assert {:ok, {:action, TestActions.Calculator}} = Registry.get("calculator")
      assert {:ok, {:action, TestActions.Search}} = Registry.get("search")
    end

    test "stops on first error" do
      result = Registry.register_actions([TestActions.Calculator, InvalidModule])
      assert {:error, :not_an_action} = result

      # First action should be registered
      assert {:ok, {:action, TestActions.Calculator}} = Registry.get("calculator")
    end
  end

  describe "register_tool/1" do
    test "registers a valid tool module" do
      assert :ok = Registry.register_tool(TestTools.Echo)
    end

    test "stores tool with correct type" do
      :ok = Registry.register_tool(TestTools.Echo)

      assert {:ok, {:tool, TestTools.Echo}} = Registry.get("echo")
    end

    test "returns error for non-tool module" do
      assert {:error, :not_a_tool} = Registry.register_tool(InvalidModule)
    end

    test "returns error for action module" do
      # Actions should not be registered via register_tool
      assert {:error, :not_a_tool} = Registry.register_tool(TestActions.Calculator)
    end
  end

  describe "register_tools/1" do
    test "registers multiple tool modules" do
      assert :ok = Registry.register_tools([TestTools.Echo, TestTools.Weather])

      assert {:ok, {:tool, TestTools.Echo}} = Registry.get("echo")
      assert {:ok, {:tool, TestTools.Weather}} = Registry.get("weather")
    end

    test "stops on first error" do
      result = Registry.register_tools([TestTools.Echo, InvalidModule])
      assert {:error, :not_a_tool} = result

      # First tool should be registered
      assert {:ok, {:tool, TestTools.Echo}} = Registry.get("echo")
    end
  end

  describe "register/1 auto-detection" do
    test "auto-detects and registers action" do
      assert :ok = Registry.register(TestActions.Calculator)
      assert {:ok, {:action, TestActions.Calculator}} = Registry.get("calculator")
    end

    test "auto-detects and registers tool" do
      assert :ok = Registry.register(TestTools.Echo)
      assert {:ok, {:tool, TestTools.Echo}} = Registry.get("echo")
    end

    test "returns error for invalid module" do
      assert {:error, :invalid_module} = Registry.register(InvalidModule)
    end
  end

  describe "get/1" do
    test "returns action with type" do
      :ok = Registry.register_action(TestActions.Calculator)
      assert {:ok, {:action, TestActions.Calculator}} = Registry.get("calculator")
    end

    test "returns tool with type" do
      :ok = Registry.register_tool(TestTools.Echo)
      assert {:ok, {:tool, TestTools.Echo}} = Registry.get("echo")
    end

    test "returns error for unknown name" do
      assert {:error, :not_found} = Registry.get("unknown")
    end
  end

  describe "get!/1" do
    test "returns action with type" do
      :ok = Registry.register_action(TestActions.Calculator)
      assert {:action, TestActions.Calculator} = Registry.get!("calculator")
    end

    test "returns tool with type" do
      :ok = Registry.register_tool(TestTools.Echo)
      assert {:tool, TestTools.Echo} = Registry.get!("echo")
    end

    test "raises KeyError for unknown name" do
      assert_raise KeyError, fn ->
        Registry.get!("unknown")
      end
    end
  end

  describe "list_all/0" do
    test "returns empty list when nothing registered" do
      assert [] = Registry.list_all()
    end

    test "returns all registered items" do
      :ok = Registry.register_action(TestActions.Calculator)
      :ok = Registry.register_tool(TestTools.Echo)

      items = Registry.list_all()
      assert length(items) == 2

      assert {"calculator", :action, TestActions.Calculator} in items
      assert {"echo", :tool, TestTools.Echo} in items
    end

    test "returns items sorted by name" do
      :ok = Registry.register_tool(TestTools.Weather)
      :ok = Registry.register_action(TestActions.Calculator)
      :ok = Registry.register_tool(TestTools.Echo)

      items = Registry.list_all()
      names = Enum.map(items, &elem(&1, 0))

      assert names == ["calculator", "echo", "weather"]
    end
  end

  describe "list_actions/0" do
    test "returns empty list when no actions registered" do
      :ok = Registry.register_tool(TestTools.Echo)
      assert [] = Registry.list_actions()
    end

    test "returns only actions" do
      :ok = Registry.register_action(TestActions.Calculator)
      :ok = Registry.register_action(TestActions.Search)
      :ok = Registry.register_tool(TestTools.Echo)

      actions = Registry.list_actions()
      assert length(actions) == 2

      assert {"calculator", TestActions.Calculator} in actions
      assert {"search", TestActions.Search} in actions
      refute Enum.any?(actions, fn {_, mod} -> mod == TestTools.Echo end)
    end
  end

  describe "list_tools/0" do
    test "returns empty list when no tools registered" do
      :ok = Registry.register_action(TestActions.Calculator)
      assert [] = Registry.list_tools()
    end

    test "returns only tools" do
      :ok = Registry.register_tool(TestTools.Echo)
      :ok = Registry.register_tool(TestTools.Weather)
      :ok = Registry.register_action(TestActions.Calculator)

      tools = Registry.list_tools()
      assert length(tools) == 2

      assert {"echo", TestTools.Echo} in tools
      assert {"weather", TestTools.Weather} in tools
      refute Enum.any?(tools, fn {_, mod} -> mod == TestActions.Calculator end)
    end
  end

  describe "to_reqllm_tools/0" do
    test "returns empty list when nothing registered" do
      assert [] = Registry.to_reqllm_tools()
    end

    test "converts actions to ReqLLM.Tool" do
      :ok = Registry.register_action(TestActions.Calculator)

      [tool] = Registry.to_reqllm_tools()
      assert %ReqLLM.Tool{} = tool
      assert tool.name == "calculator"
      assert tool.description == "Performs arithmetic calculations"
    end

    test "converts tools to ReqLLM.Tool" do
      :ok = Registry.register_tool(TestTools.Echo)

      [tool] = Registry.to_reqllm_tools()
      assert %ReqLLM.Tool{} = tool
      assert tool.name == "echo"
      assert tool.description == "Echoes back the input message"
    end

    test "converts mixed actions and tools" do
      :ok = Registry.register_action(TestActions.Calculator)
      :ok = Registry.register_tool(TestTools.Echo)

      tools = Registry.to_reqllm_tools()
      assert length(tools) == 2

      names = Enum.map(tools, & &1.name)
      assert "calculator" in names
      assert "echo" in names
    end
  end

  describe "clear/0" do
    test "removes all registered items" do
      :ok = Registry.register_action(TestActions.Calculator)
      :ok = Registry.register_tool(TestTools.Echo)

      assert length(Registry.list_all()) == 2

      :ok = Registry.clear()

      assert [] = Registry.list_all()
    end
  end

  describe "unregister/1" do
    test "removes registered item by name" do
      :ok = Registry.register_action(TestActions.Calculator)
      :ok = Registry.register_tool(TestTools.Echo)

      assert length(Registry.list_all()) == 2

      :ok = Registry.unregister("calculator")

      assert length(Registry.list_all()) == 1
      assert {:error, :not_found} = Registry.get("calculator")
      assert {:ok, {:tool, TestTools.Echo}} = Registry.get("echo")
    end

    test "returns ok for non-existent name" do
      assert :ok = Registry.unregister("unknown")
    end
  end

  describe "concurrent access" do
    test "handles multiple concurrent registrations" do
      tasks =
        for i <- 1..10 do
          Task.async(fn ->
            # Alternate between registering action and tool
            if rem(i, 2) == 0 do
              Registry.register_action(TestActions.Calculator)
            else
              Registry.register_tool(TestTools.Echo)
            end
          end)
        end

      Enum.each(tasks, &Task.await/1)

      # Both should be registered (last write wins for duplicates)
      items = Registry.list_all()
      # We should have at most 2 items (calculator and echo)
      assert length(items) <= 2
    end
  end
end
