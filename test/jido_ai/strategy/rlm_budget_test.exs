defmodule Jido.AI.Strategies.RLMBudgetTest do
  use ExUnit.Case, async: true

  alias Jido.Agent.Strategy.State, as: StratState
  alias Jido.AI.Strategies.RLM
  alias Jido.AI.RLM.BudgetStore

  defp create_agent(opts \\ []) do
    %Jido.Agent{
      id: "test-rlm-budget-agent",
      name: "test_rlm_budget",
      state: %{}
    }
    |> then(fn agent ->
      ctx = %{strategy_opts: opts}
      {agent, []} = RLM.init(agent, ctx)
      agent
    end)
  end

  defp run_cmd(agent, action, params) do
    instruction = %Jido.Instruction{action: action, params: params}
    RLM.cmd(agent, [instruction], %{})
  end

  describe "config includes budget options" do
    test "config includes max_children_total and token_budget" do
      agent = create_agent(max_children_total: 10, token_budget: 50_000)
      state = StratState.get(agent, %{})
      config = state[:config]

      assert config[:max_children_total] == 10
      assert config[:token_budget] == 50_000
    end
  end

  describe "budget created on start" do
    test "creates budget when config has budget opts" do
      agent = create_agent(max_children_total: 5, token_budget: 10_000)

      {agent, _directives} =
        run_cmd(agent, RLM.start_action(), %{
          query: "test query",
          context: "some context data"
        })

      state = StratState.get(agent, %{})
      assert state[:budget_ref] != nil
      assert state[:owns_budget] == true

      BudgetStore.destroy(state[:budget_ref])
    end
  end

  describe "budget inherited from tool_context" do
    test "inherits budget_ref from tool_context" do
      {:ok, existing_ref} = BudgetStore.new("parent-budget", max_children_total: 20)

      agent = create_agent(max_children_total: 5)

      {agent, _directives} =
        run_cmd(agent, RLM.start_action(), %{
          query: "test query",
          context: "some context data",
          tool_context: %{budget_ref: existing_ref}
        })

      state = StratState.get(agent, %{})
      assert state[:budget_ref] == existing_ref
      assert state[:owns_budget] == false

      BudgetStore.destroy(existing_ref)
    end
  end

  describe "usage action tracks tokens" do
    test "tracks tokens via usage action" do
      agent = create_agent(token_budget: 1000)

      {agent, _directives} =
        run_cmd(agent, RLM.start_action(), %{
          query: "test query",
          context: "some context data"
        })

      state = StratState.get(agent, %{})
      budget_ref = state[:budget_ref]
      assert budget_ref != nil

      {agent, _directives} =
        run_cmd(agent, RLM.usage_action(), %{
          usage: %{total_tokens: 500}
        })

      status = BudgetStore.status(budget_ref)
      assert status.tokens_used == 500

      state = StratState.get(agent, %{})
      refute state[:budget_exceeded]

      BudgetStore.destroy(budget_ref)
    end
  end

  describe "usage action sets budget_exceeded" do
    test "sets budget_exceeded when tokens exceed budget" do
      agent = create_agent(token_budget: 100)

      {agent, _directives} =
        run_cmd(agent, RLM.start_action(), %{
          query: "test query",
          context: "some context data"
        })

      state = StratState.get(agent, %{})
      budget_ref = state[:budget_ref]
      assert budget_ref != nil

      {agent, _directives} =
        run_cmd(agent, RLM.usage_action(), %{
          usage: %{total_tokens: 200}
        })

      state = StratState.get(agent, %{})
      assert state[:budget_exceeded] == true

      BudgetStore.destroy(budget_ref)
    end
  end

  describe "auto-spawn config" do
    test "defaults to off" do
      agent = create_agent()
      state = StratState.get(agent, %{})
      config = state[:config]

      assert config[:auto_spawn?] == false
    end

    test "can be enabled with threshold" do
      agent = create_agent(auto_spawn?: true, auto_spawn_threshold_bytes: 1000)
      state = StratState.get(agent, %{})
      config = state[:config]

      assert config[:auto_spawn?] == true
      assert config[:auto_spawn_threshold_bytes] == 1000
    end
  end

  describe "budget cleanup on finalize" do
    test "budget GenServer is stopped when owns_budget is true" do
      {:ok, budget_ref} = BudgetStore.new("cleanup-test", max_children_total: 5)

      assert Process.alive?(budget_ref.pid)

      BudgetStore.destroy(budget_ref)

      refute Process.alive?(budget_ref.pid)
    end

    test "budget not destroyed when owns_budget is false" do
      {:ok, budget_ref} = BudgetStore.new("no-cleanup-test", max_children_total: 5)

      assert Process.alive?(budget_ref.pid)

      status = BudgetStore.status(budget_ref)
      assert status.children_max == 5

      BudgetStore.destroy(budget_ref)
    end
  end
end
