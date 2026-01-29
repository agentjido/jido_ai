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

  # Additional test Action modules
  defmodule TestActions.Echo do
    use Jido.Action,
      name: "echo",
      description: "Echoes back the input message",
      schema: [
        message: [type: :string, required: true, doc: "Message to echo"]
      ]

    @impl true
    def run(params, _context) do
      {:ok, %{message: params.message}}
    end
  end

  defmodule TestActions.Weather do
    use Jido.Action,
      name: "weather",
      description: "Gets weather information",
      schema: [
        city: [type: :string, required: true, doc: "City name"]
      ]

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

    test "stores action module" do
      :ok = Registry.register_action(TestActions.Calculator)

      assert {:ok, TestActions.Calculator} = Registry.get("calculator")
    end

    test "returns error for non-action module" do
      assert {:error, :not_an_action} = Registry.register_action(InvalidModule)
    end
  end

  describe "register_actions/1" do
    test "registers multiple action modules" do
      assert :ok = Registry.register_actions([TestActions.Calculator, TestActions.Search])

      assert {:ok, TestActions.Calculator} = Registry.get("calculator")
      assert {:ok, TestActions.Search} = Registry.get("search")
    end

    test "stops on first error" do
      result = Registry.register_actions([TestActions.Calculator, InvalidModule])
      assert {:error, :not_an_action} = result

      # First action should be registered
      assert {:ok, TestActions.Calculator} = Registry.get("calculator")
    end
  end

  describe "register/1" do
    test "registers action" do
      assert :ok = Registry.register(TestActions.Calculator)
      assert {:ok, TestActions.Calculator} = Registry.get("calculator")
    end

    test "returns error for invalid module" do
      assert {:error, :not_an_action} = Registry.register(InvalidModule)
    end
  end

  describe "get/1" do
    test "returns action module" do
      :ok = Registry.register_action(TestActions.Calculator)
      assert {:ok, TestActions.Calculator} = Registry.get("calculator")
    end

    test "returns error for unknown name" do
      assert {:error, :not_found} = Registry.get("unknown")
    end
  end

  describe "get!/1" do
    test "returns action module" do
      :ok = Registry.register_action(TestActions.Calculator)
      assert TestActions.Calculator = Registry.get!("calculator")
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
      :ok = Registry.register_action(TestActions.Echo)

      items = Registry.list_all()
      assert length(items) == 2

      assert {"calculator", TestActions.Calculator} in items
      assert {"echo", TestActions.Echo} in items
    end

    test "returns items sorted by name" do
      :ok = Registry.register_action(TestActions.Weather)
      :ok = Registry.register_action(TestActions.Calculator)
      :ok = Registry.register_action(TestActions.Echo)

      items = Registry.list_all()
      names = Enum.map(items, &elem(&1, 0))

      assert names == ["calculator", "echo", "weather"]
    end
  end

  describe "list_actions/0" do
    test "returns empty list when no actions registered" do
      assert [] = Registry.list_actions()
    end

    test "returns only actions" do
      :ok = Registry.register_action(TestActions.Calculator)
      :ok = Registry.register_action(TestActions.Search)
      :ok = Registry.register_action(TestActions.Echo)

      actions = Registry.list_actions()
      assert length(actions) == 3

      assert {"calculator", TestActions.Calculator} in actions
      assert {"search", TestActions.Search} in actions
      assert {"echo", TestActions.Echo} in actions
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

    test "converts multiple actions to ReqLLM.Tool" do
      :ok = Registry.register_action(TestActions.Calculator)
      :ok = Registry.register_action(TestActions.Echo)

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
      :ok = Registry.register_action(TestActions.Echo)

      assert length(Registry.list_all()) == 2

      :ok = Registry.clear()

      assert [] = Registry.list_all()
    end
  end

  describe "unregister/1" do
    test "removes registered item by name" do
      :ok = Registry.register_action(TestActions.Calculator)
      :ok = Registry.register_action(TestActions.Echo)

      assert length(Registry.list_all()) == 2

      :ok = Registry.unregister("calculator")

      assert length(Registry.list_all()) == 1
      assert {:error, :not_found} = Registry.get("calculator")
      assert {:ok, TestActions.Echo} = Registry.get("echo")
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
            if rem(i, 2) == 0 do
              Registry.register_action(TestActions.Calculator)
            else
              Registry.register_action(TestActions.Echo)
            end
          end)
        end

      Enum.each(tasks, &Task.await/1)

      items = Registry.list_all()
      assert length(items) <= 2
    end
  end
end
