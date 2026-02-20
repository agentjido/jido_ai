defmodule Jido.AI.AoTAgentTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Request

  defmodule TestAoTAgent do
    use Jido.AI.AoTAgent,
      name: "test_aot_agent",
      model: "test:model",
      profile: :short,
      search_style: :bfs,
      temperature: 0.2,
      max_tokens: 1024,
      require_explicit_answer: false
  end

  defmodule DefaultAoTAgent do
    use Jido.AI.AoTAgent,
      name: "default_aot_agent"
  end

  describe "module creation" do
    test "creates agent module with expected name" do
      assert TestAoTAgent.name() == "test_aot_agent"
    end

    test "defines explore and explore_sync helpers" do
      assert function_exported?(TestAoTAgent, :explore, 2)
      assert function_exported?(TestAoTAgent, :explore_sync, 2)
      assert function_exported?(TestAoTAgent, :await, 1)
    end
  end

  describe "strategy configuration" do
    test "uses AlgorithmOfThoughts strategy" do
      assert TestAoTAgent.strategy() == Jido.AI.Reasoning.AlgorithmOfThoughts.Strategy
    end

    test "passes custom AoT options to strategy" do
      opts = TestAoTAgent.strategy_opts()

      assert opts[:model] == "test:model"
      assert opts[:profile] == :short
      assert opts[:search_style] == :bfs
      assert opts[:temperature] == 0.2
      assert opts[:max_tokens] == 1024
      assert opts[:require_explicit_answer] == false
    end

    test "uses expected defaults when not provided" do
      opts = DefaultAoTAgent.strategy_opts()

      assert opts[:model] == "anthropic:claude-haiku-4-5"
      assert opts[:profile] == :standard
      assert opts[:search_style] == :dfs
      assert opts[:temperature] == 0.0
      assert opts[:max_tokens] == 2048
      assert opts[:require_explicit_answer] == true
    end
  end

  describe "request lifecycle hooks" do
    test "on_before_cmd marks request as failed on aot_request_error" do
      agent = TestAoTAgent.new()
      agent = Request.start_request(agent, "req_1", "query")

      {:ok, agent, _action} =
        TestAoTAgent.on_before_cmd(
          agent,
          {:aot_request_error, %{request_id: "req_1", reason: :busy, message: "busy"}}
        )

      assert get_in(agent.state, [:requests, "req_1", :status]) == :failed
      assert get_in(agent.state, [:requests, "req_1", :error]) == {:rejected, :busy, "busy"}
    end
  end
end
