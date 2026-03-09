defmodule Jido.AI.AdaptiveAgentTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Request
  alias Jido.AI.Reasoning.Adaptive.Strategy, as: Adaptive
  alias Jido.AI.Reasoning.ChainOfDraft.Strategy, as: ChainOfDraft

  defmodule TestAdaptiveAgent do
    use Jido.AI.AdaptiveAgent,
      name: "test_adaptive_agent",
      model: "test:model",
      default_strategy: :cot,
      available_strategies: [:cot, :react, :tot]
  end

  defmodule DefaultAdaptiveAgent do
    use Jido.AI.AdaptiveAgent,
      name: "default_adaptive_agent"
  end

  describe "strategy configuration" do
    test "uses Adaptive strategy" do
      assert TestAdaptiveAgent.strategy() == Adaptive
    end

    test "passes custom strategy options to adaptive strategy" do
      opts = TestAdaptiveAgent.strategy_opts()

      assert opts[:model] == "test:model"
      assert opts[:default_strategy] == :cot
      assert opts[:available_strategies] == [:cot, :react, :tot]
      refute Keyword.has_key?(opts, :complexity_thresholds)
    end

    test "uses expected defaults when not provided" do
      opts = DefaultAdaptiveAgent.strategy_opts()

      assert opts[:model] == :fast
      assert opts[:default_strategy] == :react
      assert opts[:available_strategies] == [:cod, :cot, :react, :tot, :got, :trm]
      refute Keyword.has_key?(opts, :complexity_thresholds)
    end
  end

  describe "request lifecycle hooks" do
    test "on_before_cmd tracks prompt and request_id on adaptive_start" do
      agent = TestAdaptiveAgent.new()

      {:ok, updated_agent, {:adaptive_start, params}} =
        TestAdaptiveAgent.on_before_cmd(agent, {:adaptive_start, %{prompt: "Compare weather routes"}})

      request_id = params.request_id
      assert is_binary(request_id)
      assert updated_agent.state.last_prompt == "Compare weather routes"
      assert get_in(updated_agent.state, [:requests, request_id, :status]) == :pending
      assert get_in(updated_agent.state, [:requests, request_id, :query]) == "Compare weather routes"
    end

    test "on_before_cmd marks request as failed on adaptive_request_error" do
      agent = TestAdaptiveAgent.new()
      agent = Request.start_request(agent, "req_1", "query")

      {:ok, agent, _action} =
        TestAdaptiveAgent.on_before_cmd(
          agent,
          {:adaptive_request_error, %{request_id: "req_1", reason: :busy, message: "busy"}}
        )

      assert get_in(agent.state, [:requests, "req_1", :status]) == :failed
      assert get_in(agent.state, [:requests, "req_1", :error]) == {:rejected, :busy, "busy"}
    end

    test "on_after_cmd completes request when strategy snapshot is done" do
      agent =
        TestAdaptiveAgent.new()
        |> Request.start_request("req_done", "query")
        |> with_completed_strategy("final recommendation")

      {:ok, updated_agent, directives} =
        TestAdaptiveAgent.on_after_cmd(agent, {:adaptive_start, %{request_id: "req_done"}}, [:noop])

      assert directives == [:noop]
      assert get_in(updated_agent.state, [:requests, "req_done", :status]) == :completed
      assert get_in(updated_agent.state, [:requests, "req_done", :result]) == "final recommendation"
      assert updated_agent.state.selected_strategy == :cod
    end

    test "on_after_cmd finalizes pending request for delegated worker events" do
      agent =
        TestAdaptiveAgent.new()
        |> Request.start_request("req_worker", "query")
        |> with_completed_strategy("worker recommendation")

      {:ok, updated_agent, directives} =
        TestAdaptiveAgent.on_after_cmd(
          agent,
          {:adaptive_worker_event, %{request_id: "req_worker", event: %{request_id: "req_worker"}}},
          [:noop]
        )

      assert directives == [:noop]
      assert get_in(updated_agent.state, [:requests, "req_worker", :status]) == :completed
      assert get_in(updated_agent.state, [:requests, "req_worker", :result]) == "worker recommendation"
      assert updated_agent.state.selected_strategy == :cod
      assert updated_agent.state.completed == true
    end

    test "on_after_cmd preserves pending request when strategy is still running" do
      agent =
        TestAdaptiveAgent.new()
        |> Request.start_request("req_running", "query")
        |> with_running_strategy()

      {:ok, updated_agent, directives} =
        TestAdaptiveAgent.on_after_cmd(agent, {:adaptive_start, %{request_id: "req_running"}}, [:noop])

      assert directives == [:noop]
      assert get_in(updated_agent.state, [:requests, "req_running", :status]) == :pending
      assert updated_agent.state.selected_strategy == :cod
    end

    test "on_after_cmd passes through adaptive_request_error action unchanged" do
      agent = TestAdaptiveAgent.new()

      {:ok, updated_agent, directives} =
        TestAdaptiveAgent.on_after_cmd(agent, {:adaptive_request_error, %{request_id: "req_1"}}, [:noop])

      assert updated_agent == agent
      assert directives == [:noop]
    end
  end

  defp with_completed_strategy(agent, result) do
    strategy_state = %{
      selected_strategy: ChainOfDraft,
      strategy_type: :cod,
      status: :completed,
      result: result
    }

    put_in(agent.state[:__strategy__], strategy_state)
  end

  defp with_running_strategy(agent) do
    strategy_state = %{
      selected_strategy: ChainOfDraft,
      strategy_type: :cod,
      status: :reasoning
    }

    put_in(agent.state[:__strategy__], strategy_state)
  end
end
