defmodule Jido.AI.ToolApiTest do
  @moduledoc """
  Tests for the public Tool Management API in Jido.AI.
  """
  use ExUnit.Case, async: true

  alias Jido.AI

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
    use Jido.AI.Agent, name: "test_tool_api_agent", description: "Agent for testing tool API"

    agent do
      schema Zoi.object(%{last_result: Zoi.any() |> Zoi.default(nil), messages: Jido.AI.Thread.Projection.schema()})

      ai :assistant do
        model(:fast)
        reasoning(:react)

        tools do
          action(Calculator)
          action(Search)
        end

        requests do
          mode(:session)
        end

        memory do
          history(:messages)
        end

        result(into: :last_result)
      end
    end

    routes do
      route("ai.react.query", ai: :assistant)
    end
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

    test "set_system_prompt forwards to AgentServer call" do
      fake_pid = spawn(fn -> :ok end)
      assert catch_exit(AI.set_system_prompt(fake_pid, "prompt", timeout: 100))
    end
  end

  describe "list_tools/1 with agent struct" do
    test "returns list of tool modules" do
      agent = TestAgent.new!()
      tools = AI.list_tools(agent)

      assert is_list(tools)
      assert Calculator in tools
      assert Search in tools
      assert length(tools) == 2
    end

    test "returns empty list for agent without tools" do
      # Test with a manually constructed agent state
      agent = TestAgent.new!()
      # Manually clear tools from strategy state for testing
      {:ok, agent} = Jido.AI.unregister_tool_direct(agent, "calculator")
      {:ok, agent} = Jido.AI.unregister_tool_direct(agent, "search")
      tools = AI.list_tools(agent)

      assert tools == []
    end
  end

  describe "has_tool?/2 with agent struct" do
    test "returns true for registered tool" do
      agent = TestAgent.new!()
      assert AI.has_tool?(agent, "calculator") == true
      assert AI.has_tool?(agent, "search") == true
    end

    test "returns false for unregistered tool" do
      agent = TestAgent.new!()
      assert AI.has_tool?(agent, "nonexistent") == false
      assert AI.has_tool?(agent, "weather") == false
    end
  end

  describe "Jido.AI.list_tools/1" do
    test "returns tool modules from agent" do
      agent = TestAgent.new!()
      tools = AI.list_tools(agent)

      assert Calculator in tools
      assert Search in tools
    end
  end
end
