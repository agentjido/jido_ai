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
      traversal_strategy: :bfs,
      top_k: 4,
      min_depth: 1,
      max_nodes: 50
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

    test "passes structured ToT options to strategy" do
      opts = TestToTAgent.strategy_opts()
      assert opts[:top_k] == 4
      assert opts[:min_depth] == 1
      assert opts[:max_nodes] == 50
    end

    test "uses default values when not specified" do
      opts = DefaultToTAgent.strategy_opts()
      assert opts[:model] == :fast
      assert opts[:branching_factor] == 3
      assert opts[:max_depth] == 3
      assert opts[:traversal_strategy] == :best_first
      assert opts[:top_k] == 3
      assert opts[:min_depth] == 2
      assert opts[:max_nodes] == 100
      assert opts[:max_duration_ms] == nil
      assert opts[:beam_width] == nil
      assert opts[:early_success_threshold] == 1.0
      assert opts[:convergence_window] == 2
      assert opts[:min_score_improvement] == 0.02
      assert opts[:max_parse_retries] == 1
      assert opts[:tool_timeout_ms] == 15_000
      assert opts[:tool_max_retries] == 1
      assert opts[:tool_retry_backoff_ms] == 200
      assert opts[:max_tool_round_trips] == 3
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
      assert agent.state.last_result == nil
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
      assert updated_agent.state.last_result == nil
    end

    test "passes through other actions unchanged" do
      agent = TestToTAgent.new()
      action = {:other_action, %{data: "test"}}

      {:ok, updated_agent, returned_action} = TestToTAgent.on_before_cmd(agent, action)

      assert updated_agent == agent
      assert returned_action == action
    end
  end

  describe "on_after_cmd/3" do
    test "finalizes pending request on terminal delegated worker event" do
      agent =
        TestToTAgent.new()
        |> Jido.AI.Request.start_request("req_done", "query")
        |> with_completed_strategy("best path")

      {:ok, updated_agent, directives} =
        TestToTAgent.on_after_cmd(
          agent,
          {:tot_worker_event, %{request_id: "req_done", event: %{request_id: "req_done"}}},
          [:noop]
        )

      assert directives == [:noop]
      assert get_in(updated_agent.state, [:requests, "req_done", :status]) == :completed
      assert get_in(updated_agent.state, [:requests, "req_done", :result]) == "best path"
      assert updated_agent.state.completed == true
      assert updated_agent.state.last_result == "best path"
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
      assert state[:top_k] == 4
      assert state[:min_depth] == 1
      assert state[:max_nodes] == 50
    end
  end

  describe "structured result helpers" do
    test "best_answer/1 and top_candidates/2 extract data from structured result" do
      result = %{
        best: %{content: "Best option"},
        candidates: [%{content: "Best option"}, %{content: "Fallback option"}],
        termination: %{reason: :max_depth},
        tree: %{node_count: 4}
      }

      assert TestToTAgent.best_answer(result) == "Best option"
      assert length(TestToTAgent.top_candidates(result, 1)) == 1

      summary = TestToTAgent.result_summary(result)
      assert summary.best_answer == "Best option"
      assert summary.termination.reason == :max_depth
    end

    test "result_summary/1 is nil-safe and keeps stable shape" do
      assert TestToTAgent.result_summary(nil) == %{
               best_answer: nil,
               top_candidates: [],
               termination: %{},
               tree: %{}
             }
    end
  end

  defp with_completed_strategy(agent, result) do
    strategy_state = %{status: :completed, result: result}
    put_in(agent.state[:__strategy__], strategy_state)
  end
end
