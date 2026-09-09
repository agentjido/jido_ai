defmodule Jido.AI.CoTAgentTest do
  use Jido.AI.Test.ReasoningCase, async: false

  defmodule TestCoTAgent do
    use Jido.AI.CoTAgent,
      name: "test_cot_agent",
      model: "openai:gpt-4o-mini"
  end

  defmodule DefaultCoTAgent do
    use Jido.AI.CoTAgent,
      name: "default_cot_agent"
  end

  defmodule PromptedCoTAgent do
    use Jido.AI.CoTAgent,
      name: "prompted_cot_agent",
      model: "openai:gpt-4",
      system_prompt: "Think in clear numbered steps."
  end

  defmodule AttrPromptCoTAgent do
    @prompt "Think with an attribute prompt."

    use Jido.AI.CoTAgent,
      name: "attr_prompt_cot_agent",
      system_prompt: @prompt
  end

  defmodule FalsePromptCoTAgent do
    use Jido.AI.CoTAgent,
      name: "false_prompt_cot_agent",
      system_prompt: false
  end

  defmodule NilPromptCoTAgent do
    use Jido.AI.CoTAgent,
      name: "nil_prompt_cot_agent",
      system_prompt: nil
  end

  describe "module creation" do
    test "defines expected helper API" do
      assert function_exported?(TestCoTAgent, :think, 2)
      assert function_exported?(TestCoTAgent, :think_sync, 2)
      assert function_exported?(TestCoTAgent, :await, 1)
      assert function_exported?(TestCoTAgent, :strategy_opts, 0)
    end
  end

  describe "strategy configuration" do
    test "selects ChainOfThought in the native AI profile" do
      assert {:ok, profile} = Configuration.profile(TestCoTAgent.definition())
      assert profile.reasoning.method == :chain_of_thought
    end

    test "uses expected defaults when not provided" do
      opts = DefaultCoTAgent.strategy_opts()

      assert opts[:model] == :fast
      refute Keyword.has_key?(opts, :system_prompt)
    end

    test "passes custom model and system_prompt options to strategy" do
      opts = PromptedCoTAgent.strategy_opts()

      assert opts[:model] == "openai:gpt-4"
      assert opts[:system_prompt] == "Think in clear numbered steps."
    end

    test "resolves system_prompt from module attribute" do
      opts = AttrPromptCoTAgent.strategy_opts()

      assert opts[:system_prompt] == "Think with an attribute prompt."
    end

    test "treats false system_prompt as omitted" do
      opts = FalsePromptCoTAgent.strategy_opts()

      refute Keyword.has_key?(opts, :system_prompt)
    end

    test "treats nil system_prompt as omitted" do
      opts = NilPromptCoTAgent.strategy_opts()

      refute Keyword.has_key?(opts, :system_prompt)
    end

    test "raises when module attribute system_prompt does not resolve to a binary" do
      module_name = Module.concat(__MODULE__, :"InvalidPromptCoTAgent#{System.unique_integer([:positive, :monotonic])}")

      source = """
      defmodule #{inspect(module_name)} do
        @prompt 123

        use Jido.AI.CoTAgent,
          name: "invalid_prompt_cot_agent",
          system_prompt: @prompt
      end
      """

      assert_raise CompileError, ~r/system_prompt must be a binary, nil, false/, fn ->
        Code.compile_string(source)
      end
    end
  end

  describe "request lifecycle" do
    test "busy admission returns the rejected request ID and keeps active work", %{jido: jido} do
      mock = mock([%{reply: {:stream, [{:wait, :held}, %{content: "Conclusion: done"}], "stop"}}])
      server = start_agent(jido, TestCoTAgent)
      opts = [model: MockLLM.model(), llm_opts: MockLLM.options(mock), stream_to: self()]
      assert {:ok, first} = TestCoTAgent.think(server, "First", opts)
      assert_receive {:mock_llm_waiting, ^mock, :held, _}, 2_000
      assert {:error, :busy} = TestCoTAgent.think(server, "Second", Keyword.put(opts, :request_id, "rejected"))
      assert_receive {:jido_ai_request_event, %{request_id: "rejected", kind: :request_failed, data: %{error: :busy}}}
      assert Map.keys(Server.agent(server).state.requests) == [first.id]
      assert :ok = MockLLM.release(mock, :held)
      assert {:ok, "done"} = TestCoTAgent.await(first)
      assert_script_done(mock)
    end

    test "completion commits the request and public result fields", %{jido: jido} do
      mock = mock([%{reply: {:text, "final reasoning"}}])
      server = start_agent(jido, TestCoTAgent)

      assert {:ok, handle} =
               TestCoTAgent.think(server, "query", model: MockLLM.model(), llm_opts: MockLLM.options(mock))

      assert {:ok, "final reasoning"} = TestCoTAgent.await(handle)
      assert record(server, handle).status == :completed
      assert record(server, handle).result == "final reasoning"
      assert Server.agent(server).state.last_result == "final reasoning"
      assert Server.agent(server).state.completed
      assert_script_done(mock)
    end

    test "completion stores usage from the provider response", %{jido: jido} do
      mock =
        mock([
          %{
            reply:
              {:stream, [%{content: "final reasoning"}], "stop",
               %{prompt_tokens: 5, completion_tokens: 2, total_tokens: 7}}
          }
        ])

      server = start_agent(jido, TestCoTAgent)

      assert {:ok, handle} =
               TestCoTAgent.think(server, "query", model: MockLLM.model(), llm_opts: MockLLM.options(mock))

      assert {:ok, "final reasoning"} = TestCoTAgent.await(handle)
      assert %{input_tokens: 5, output_tokens: 2, total_tokens: 7} = record(server, handle).meta.usage
      assert record(server, handle).meta.model_calls == 1
      assert_script_done(mock)
    end

    test "failure stores the provider cause and closes the pending request", %{jido: jido} do
      mock = mock([%{reply: {:error, 503, "busy"}}])
      server = start_agent(jido, TestCoTAgent)

      assert {:ok, handle} =
               TestCoTAgent.think(server, "query", model: MockLLM.model(), llm_opts: MockLLM.options(mock))

      assert {:error, error} = TestCoTAgent.await(handle)
      assert %ReqLLM.Error.API.Stream{cause: %ReqLLM.Error.API.Request{status: 503, reason: "busy"}} = error
      assert error.cause.response_body["message"] == "busy"
      assert record(server, handle).status == :failed
      assert record(server, handle).error == error
      assert Server.agent(server).state.last_result == inspect(error)
      assert Server.agent(server).state.completed
      assert_script_done(mock)
    end
  end

  describe "macro docs contract" do
    test "documents request lifecycle behavior for think/await helpers" do
      doc = moduledoc!(Jido.AI.CoTAgent)

      assert doc =~ "Request Lifecycle Contract"
      assert doc =~ "think/3"
      assert doc =~ "await/2"
      assert doc =~ "think_sync/3"
      assert doc =~ "ai.cot.query"
      assert doc =~ "Default request policy is `:reject`"
      assert doc =~ "ai.request.error"
    end
  end

  defp moduledoc!(module) do
    {:docs_v1, _, _, _, moduledoc, _, _} = Code.fetch_docs(module)

    case moduledoc do
      %{"en" => doc} when is_binary(doc) -> doc
      doc when is_binary(doc) -> doc
    end
  end
end
