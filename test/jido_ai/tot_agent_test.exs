defmodule Jido.AI.ToTAgentTest do
  use ExUnit.Case, async: true

  alias Jido.Agent.Strategy.State, as: StratState

  defmodule TestToTAgent do
    use Jido.AI.ToTAgent,
      name: "test_tot_agent",
      description: "Test ToT agent for unit tests",
      model: "test:model",
      branching_factor: 2,
      max_depth: 2,
      traversal_strategy: :bfs
  end

  defmodule DefaultToTAgent do
    use Jido.AI.ToTAgent,
      name: "default_tot_agent"
  end

  describe "module creation" do
    test "creates agent module with expected name" do
      assert TestToTAgent.name() == "test_tot_agent"
    end

    test "creates agent module with expected description" do
      assert TestToTAgent.description() == "Test ToT agent for unit tests"
    end

    test "uses default description when not provided" do
      assert DefaultToTAgent.description() == "ToT agent default_tot_agent"
    end

    test "defines explore/2 function" do
      assert function_exported?(TestToTAgent, :explore, 2)
    end
  end

  describe "strategy configuration" do
    test "uses TreeOfThoughts strategy" do
      assert TestToTAgent.strategy() == Jido.AI.Reasoning.TreeOfThoughts.Strategy
    end

    test "passes custom model to strategy" do
      opts = TestToTAgent.strategy_opts()
      assert opts[:model] == "test:model"
    end

    test "passes custom branching_factor to strategy" do
      opts = TestToTAgent.strategy_opts()
      assert opts[:branching_factor] == 2
    end

    test "passes custom max_depth to strategy" do
      opts = TestToTAgent.strategy_opts()
      assert opts[:max_depth] == 2
    end

    test "passes custom traversal_strategy to strategy" do
      opts = TestToTAgent.strategy_opts()
      assert opts[:traversal_strategy] == :bfs
    end

    test "uses default values when not specified" do
      opts = DefaultToTAgent.strategy_opts()
      assert opts[:model] == "anthropic:claude-haiku-4-5"
      assert opts[:branching_factor] == 3
      assert opts[:max_depth] == 3
      assert opts[:traversal_strategy] == :best_first
    end
  end

  describe "state schema" do
    test "includes model field" do
      agent = TestToTAgent.new()
      assert Map.has_key?(agent.state, :model)
    end

    test "includes last_prompt field" do
      agent = TestToTAgent.new()
      assert Map.has_key?(agent.state, :last_prompt)
      assert agent.state.last_prompt == ""
    end

    test "includes last_result field" do
      agent = TestToTAgent.new()
      assert Map.has_key?(agent.state, :last_result)
      assert agent.state.last_result == ""
    end

    test "includes completed field" do
      agent = TestToTAgent.new()
      assert Map.has_key?(agent.state, :completed)
      assert agent.state.completed == false
    end
  end

  describe "plugins" do
    test "includes TaskSupervisorSkill" do
      plugins = TestToTAgent.plugins()

      plugin_mods =
        Enum.map(plugins, fn
          {mod, _opts} -> mod
          mod when is_atom(mod) -> mod
        end)

      assert Jido.AI.Plugins.TaskSupervisor in plugin_mods
    end
  end

  describe "on_before_cmd/2" do
    test "captures last_prompt on tot_start" do
      agent = TestToTAgent.new()
      action = {:tot_start, %{prompt: "Test prompt"}}

      {:ok, updated_agent, _action} = TestToTAgent.on_before_cmd(agent, action)

      assert updated_agent.state.last_prompt == "Test prompt"
      assert updated_agent.state.completed == false
      assert updated_agent.state.last_result == ""
    end

    test "passes through other actions unchanged" do
      agent = TestToTAgent.new()
      action = {:other_action, %{data: "test"}}

      {:ok, updated_agent, returned_action} = TestToTAgent.on_before_cmd(agent, action)

      assert updated_agent == agent
      assert returned_action == action
    end
  end

  describe "strategy state" do
    test "agent initializes with strategy state" do
      agent = TestToTAgent.new()
      ctx = %{strategy_opts: TestToTAgent.strategy_opts()}
      {agent, _directives} = Jido.AI.Reasoning.TreeOfThoughts.Strategy.init(agent, ctx)

      state = StratState.get(agent, %{})
      assert state[:status] == :idle
      assert state[:branching_factor] == 2
      assert state[:max_depth] == 2
      assert state[:traversal_strategy] == :bfs
    end
  end
end
