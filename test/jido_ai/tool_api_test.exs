defmodule Jido.AI.ToolApiTest do
  @moduledoc """
  Tests for the public Tool Management API in Jido.AI.
  """
  use ExUnit.Case, async: true

  alias Jido.AI
  alias Jido.AI.Strategies.ReAct

  # Test action modules
  defmodule Calculator do
    use Jido.Action,
      name: "calculator",
      description: "A calculator tool"

    def run(%{a: a, b: b}, _ctx), do: {:ok, %{result: a + b}}
  end

  defmodule Search do
    use Jido.Action,
      name: "search",
      description: "A search tool"

    def run(%{query: query}, _ctx), do: {:ok, %{results: ["Found: #{query}"]}}
  end

  defmodule Weather do
    use Jido.Action,
      name: "weather",
      description: "Weather lookup"

    def run(%{city: city}, _ctx), do: {:ok, %{temp: 72, city: city}}
  end

  # Test agent
  defmodule TestAgent do
    use Jido.AI.Agent,
      name: "test_tool_api_agent",
      description: "Agent for testing tool API",
      tools: [Calculator, Search]
  end

  # Not a tool - for validation tests
  defmodule NotATool do
    def some_function, do: :ok
  end

  describe "validate_tool_module/1" do
    test "returns error for non-tool module" do
      assert {:error, :not_a_tool} = AI.register_tool(self(), NotATool)
    end

    test "returns error for non-existent module" do
      assert {:error, {:not_loaded, NonExistentModule}} =
               AI.register_tool(self(), NonExistentModule)
    end

    test "skips validation when validate: false" do
      # When validation is skipped, registration proceeds to AgentServer call
      # Using a fake pid will fail at the GenServer call level (exits)
      fake_pid = spawn(fn -> :ok end)

      # The GenServer.call will exit because the process is dead
      assert catch_exit(AI.register_tool(fake_pid, NotATool, validate: false, timeout: 100))
    end
  end

  describe "list_tools/1 with agent struct" do
    test "returns list of tool modules" do
      agent = TestAgent.new()
      tools = AI.list_tools(agent)

      assert is_list(tools)
      assert Calculator in tools
      assert Search in tools
      assert length(tools) == 2
    end

    test "returns empty list for agent without tools" do
      # Test with a manually constructed agent state
      agent = TestAgent.new()
      # Manually clear tools from strategy state for testing
      state = Jido.Agent.Strategy.State.get(agent, %{})
      config = state[:config] || %{}
      new_config = Map.put(config, :tools, [])

      new_state =
        Map.put(state, :config, new_config)

      agent = Jido.Agent.Strategy.State.put(agent, new_state)
      tools = AI.list_tools(agent)

      assert tools == []
    end
  end

  describe "has_tool?/2 with agent struct" do
    test "returns true for registered tool" do
      agent = TestAgent.new()
      assert AI.has_tool?(agent, "calculator") == true
      assert AI.has_tool?(agent, "search") == true
    end

    test "returns false for unregistered tool" do
      agent = TestAgent.new()
      assert AI.has_tool?(agent, "nonexistent") == false
      assert AI.has_tool?(agent, "weather") == false
    end
  end

  describe "ReAct.list_tools/1 direct access" do
    test "returns tool modules from agent" do
      agent = TestAgent.new()
      tools = ReAct.list_tools(agent)

      assert Calculator in tools
      assert Search in tools
    end
  end
end
