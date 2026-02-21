defmodule Jido.AI.GoTAgentTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Request
  alias Jido.AI.Reasoning.GraphOfThoughts.Strategy, as: GraphOfThoughts

  defmodule TestGoTAgent do
    use Jido.AI.GoTAgent,
      name: "test_got_agent",
      model: "test:model",
      max_nodes: 24,
      max_depth: 7,
      aggregation_strategy: :weighted
  end

  defmodule DefaultGoTAgent do
    use Jido.AI.GoTAgent,
      name: "default_got_agent"
  end

  describe "strategy configuration" do
    test "uses GraphOfThoughts strategy" do
      assert TestGoTAgent.strategy() == GraphOfThoughts
    end

    test "passes custom GoT options to strategy" do
      opts = TestGoTAgent.strategy_opts()

      assert opts[:model] == "test:model"
      assert opts[:max_nodes] == 24
      assert opts[:max_depth] == 7
      assert opts[:aggregation_strategy] == :weighted
    end

    test "uses expected defaults when not provided" do
      opts = DefaultGoTAgent.strategy_opts()

      assert opts[:model] == :fast
      assert opts[:max_nodes] == 20
      assert opts[:max_depth] == 5
      assert opts[:aggregation_strategy] == :synthesis
    end
  end

  describe "request lifecycle hooks" do
    test "on_before_cmd tracks prompt and request_id on got_start" do
      agent = TestGoTAgent.new()

      {:ok, updated_agent, {:got_start, params}} =
        TestGoTAgent.on_before_cmd(agent, {:got_start, %{prompt: "Compare city weather risks"}})

      request_id = params.request_id
      assert is_binary(request_id)
      assert updated_agent.state.last_prompt == "Compare city weather risks"
      assert get_in(updated_agent.state, [:requests, request_id, :status]) == :pending
      assert get_in(updated_agent.state, [:requests, request_id, :query]) == "Compare city weather risks"
    end

    test "on_before_cmd marks request as failed on got_request_error" do
      agent = TestGoTAgent.new()
      agent = Request.start_request(agent, "req_1", "query")

      {:ok, agent, _action} =
        TestGoTAgent.on_before_cmd(
          agent,
          {:got_request_error, %{request_id: "req_1", reason: :busy, message: "busy"}}
        )

      assert get_in(agent.state, [:requests, "req_1", :status]) == :failed
      assert get_in(agent.state, [:requests, "req_1", :error]) == {:rejected, :busy, "busy"}
    end

    test "on_after_cmd completes request when strategy snapshot is done" do
      agent =
        TestGoTAgent.new()
        |> Request.start_request("req_done", "query")
        |> with_completed_strategy("final synthesis")

      {:ok, agent, directives} =
        TestGoTAgent.on_after_cmd(agent, {:got_start, %{request_id: "req_done"}}, [:noop])

      assert directives == [:noop]
      assert get_in(agent.state, [:requests, "req_done", :status]) == :completed
      assert get_in(agent.state, [:requests, "req_done", :result]) == "final synthesis"
      assert agent.state.last_result == "final synthesis"
      assert agent.state.completed == true
    end

    test "on_after_cmd finalizes pending request for delegated worker events" do
      agent =
        TestGoTAgent.new()
        |> Request.start_request("req_worker", "query")
        |> with_completed_strategy("worker synthesis")

      {:ok, updated_agent, directives} =
        TestGoTAgent.on_after_cmd(
          agent,
          {:got_worker_event, %{request_id: "req_worker", event: %{request_id: "req_worker"}}},
          [:noop]
        )

      assert directives == [:noop]
      assert get_in(updated_agent.state, [:requests, "req_worker", :status]) == :completed
      assert get_in(updated_agent.state, [:requests, "req_worker", :result]) == "worker synthesis"
      assert updated_agent.state.last_result == "worker synthesis"
      assert updated_agent.state.completed == true
    end

    test "on_after_cmd passes through got_request_error action unchanged" do
      agent = TestGoTAgent.new()

      {:ok, updated_agent, directives} =
        TestGoTAgent.on_after_cmd(agent, {:got_request_error, %{request_id: "req_1"}}, [:noop])

      assert updated_agent == agent
      assert directives == [:noop]
    end
  end

  defp with_completed_strategy(agent, result) do
    strategy_state = %{status: :completed, result: result, nodes: %{}, edges: []}
    put_in(agent.state[:__strategy__], strategy_state)
  end
end
