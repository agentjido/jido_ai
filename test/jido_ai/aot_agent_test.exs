defmodule Jido.AI.AoTAgentTest do
  use Jido.AI.Test.ReasoningCase, async: false

  defmodule TestAoTAgent do
    use Jido.AI.AoTAgent,
      name: "test_aot_agent",
      model: "openai:gpt-4o-mini",
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
    test "selects AlgorithmOfThoughts in the native profile" do
      assert {:ok, profile} = Configuration.profile(TestAoTAgent.definition())
      assert profile.reasoning.method == :algorithm_of_thoughts
    end

    test "passes custom AoT options to strategy" do
      opts = TestAoTAgent.strategy_opts()

      assert opts[:model] == "openai:gpt-4o-mini"
      assert opts[:profile] == :short
      assert opts[:search_style] == :bfs
      assert opts[:temperature] == 0.2
      assert opts[:max_tokens] == 1024
      assert opts[:require_explicit_answer] == false
    end

    test "uses expected defaults when not provided" do
      opts = DefaultAoTAgent.strategy_opts()

      assert opts[:model] == :fast
      assert opts[:profile] == :standard
      assert opts[:search_style] == :dfs
      assert opts[:temperature] == 0.0
      assert opts[:max_tokens] == 2048
      assert opts[:require_explicit_answer] == true
    end
  end

  describe "request lifecycle" do
    test "busy admission keeps the active request and sends correlated failure", %{jido: jido} do
      mock = mock([%{reply: {:stream, [{:wait, :held}, %{content: "answer: done"}], "stop"}}])
      server = start_agent(jido, TestAoTAgent)
      opts = [model: MockLLM.model(), llm_opts: MockLLM.options(mock), stream_to: self()]
      assert {:ok, first} = TestAoTAgent.explore(server, "first", opts)
      assert_receive {:mock_llm_waiting, ^mock, :held, _}, 2_000
      assert {:error, :busy} = TestAoTAgent.explore(server, "second", Keyword.put(opts, :request_id, "rejected"))
      assert_receive {:jido_ai_request_event, %{request_id: "rejected", kind: :request_failed, data: %{error: :busy}}}
      assert Map.keys(Server.agent(server).state.requests) == [first.id]
      assert record(server, first).status == :pending
      assert :ok = MockLLM.release(mock, :held)
      assert {:ok, %{answer: "done"}} = TestAoTAgent.await(first)
      assert_script_done(mock)
    end

    test "completion stores the full result in both request and public state", %{jido: jido} do
      mock = mock([%{reply: {:text, "answer: resolved"}}])
      server = start_agent(jido, TestAoTAgent)

      assert {:ok, handle} =
               TestAoTAgent.explore(server, "query", model: MockLLM.model(), llm_opts: MockLLM.options(mock))

      assert {:ok, result} = TestAoTAgent.await(handle)
      assert result.answer == "resolved"
      assert record(server, handle).status == :completed
      assert record(server, handle).result == result
      assert Server.agent(server).state.last_result == result
      assert Server.agent(server).state.completed
      assert_script_done(mock)
    end
  end
end
