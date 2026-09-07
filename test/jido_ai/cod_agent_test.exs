defmodule Jido.AI.CoDAgentTest do
  use Jido.AI.Test.ReasoningCase, async: false

  alias Jido.AI.Reasoning.ChainOfDraft

  defmodule TestCoDAgent do
    use Jido.AI.CoDAgent,
      name: "test_cod_agent",
      model: "openai:gpt-4o-mini"
  end

  defmodule DefaultCoDAgent do
    use Jido.AI.CoDAgent,
      name: "default_cod_agent"
  end

  defmodule PromptedCoDAgent do
    use Jido.AI.CoDAgent,
      name: "prompted_cod_agent",
      model: "openai:gpt-4",
      system_prompt: "Draft with terse steps."
  end

  defmodule AttrPromptCoDAgent do
    @prompt "Draft with an attribute prompt."

    use Jido.AI.CoDAgent,
      name: "attr_prompt_cod_agent",
      system_prompt: @prompt
  end

  defmodule FalsePromptCoDAgent do
    use Jido.AI.CoDAgent,
      name: "false_prompt_cod_agent",
      system_prompt: false
  end

  defmodule NilPromptCoDAgent do
    use Jido.AI.CoDAgent,
      name: "nil_prompt_cod_agent",
      system_prompt: nil
  end

  describe "strategy configuration" do
    test "selects ChainOfDraft in the native AI profile" do
      assert {:ok, profile} = Configuration.profile(DefaultCoDAgent.agent())
      assert profile.reasoning.method == :chain_of_draft
    end

    test "uses expected defaults when not provided" do
      opts = DefaultCoDAgent.strategy_opts()

      assert opts[:model] == :fast
      assert opts[:system_prompt] == ChainOfDraft.default_system_prompt()
    end

    test "passes custom model and system_prompt options to strategy" do
      opts = PromptedCoDAgent.strategy_opts()

      assert opts[:model] == "openai:gpt-4"
      assert opts[:system_prompt] == "Draft with terse steps."
    end

    test "resolves system_prompt from module attribute" do
      opts = AttrPromptCoDAgent.strategy_opts()

      assert opts[:system_prompt] == "Draft with an attribute prompt."
    end

    test "treats false system_prompt as default prompt" do
      opts = FalsePromptCoDAgent.strategy_opts()

      assert opts[:system_prompt] == ChainOfDraft.default_system_prompt()
    end

    test "treats nil system_prompt as default prompt" do
      opts = NilPromptCoDAgent.strategy_opts()

      assert opts[:system_prompt] == ChainOfDraft.default_system_prompt()
    end

    test "raises when module attribute system_prompt does not resolve to a binary" do
      module_name = Module.concat(__MODULE__, :"InvalidPromptCoDAgent#{System.unique_integer([:positive, :monotonic])}")

      source = """
      defmodule #{inspect(module_name)} do
        @prompt 123

        use Jido.AI.CoDAgent,
          name: "invalid_prompt_cod_agent",
          system_prompt: @prompt
      end
      """

      assert_raise CompileError, ~r/system_prompt must be a binary, nil, false/, fn ->
        Code.compile_string(source)
      end
    end
  end

  describe "request lifecycle" do
    test "failure keeps last_result printable and stores the provider error", %{jido: jido} do
      mock = mock([%{reply: {:error, 503, "busy"}}])
      server = start_agent(jido, TestCoDAgent)

      assert {:ok, handle} =
               TestCoDAgent.draft(server, "query", model: MockLLM.model(), llm_opts: MockLLM.options(mock))

      assert {:error, error} = TestCoDAgent.await(handle)
      assert %ReqLLM.Error.API.Stream{cause: %ReqLLM.Error.API.Request{status: 503, reason: "busy"}} = error
      assert error.cause.response_body["message"] == "busy"
      assert record(server, handle).status == :failed
      assert record(server, handle).error == error
      assert Server.agent(server).state.last_result == inspect(error)
      assert Server.agent(server).state.completed
      assert_script_done(mock)
    end
  end
end
