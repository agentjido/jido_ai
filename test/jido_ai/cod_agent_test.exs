defmodule Jido.AI.CoDAgentTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Request
  alias Jido.AI.Reasoning.ChainOfDraft
  alias Jido.AI.Reasoning.ChainOfDraft.Strategy, as: ChainOfDraftStrategy

  defmodule TestCoDAgent do
    use Jido.AI.CoDAgent,
      name: "test_cod_agent",
      model: "test:model"
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
    test "uses ChainOfDraft strategy" do
      assert DefaultCoDAgent.strategy() == ChainOfDraftStrategy
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

  describe "request lifecycle hooks" do
    test "on_after_cmd keeps last_result string while request failure stores raw term" do
      raw_error = %{type: :provider_error, status: 503, message: "busy"}

      agent =
        TestCoDAgent.new()
        |> Request.start_request("req_failed", "query")
        |> with_failed_strategy("req_failed", raw_error)

      {:ok, updated_agent, directives} =
        TestCoDAgent.on_after_cmd(
          agent,
          {:cod_worker_event, %{request_id: "req_failed", event: %{request_id: "req_failed"}}},
          [:noop]
        )

      assert directives == [:noop]
      assert get_in(updated_agent.state, [:requests, "req_failed", :status]) == :failed
      assert match?({:failed, _, ^raw_error}, get_in(updated_agent.state, [:requests, "req_failed", :error]))

      assert updated_agent.state.last_result == inspect(raw_error)
      assert updated_agent.state.completed == true
    end
  end

  defp with_failed_strategy(agent, request_id, result) do
    failed_event = %{
      id: "evt_failed",
      seq: 1,
      at_ms: 1_700_000_000_100,
      run_id: request_id,
      request_id: request_id,
      iteration: 1,
      kind: :request_failed,
      llm_call_id: "cod_call_1",
      tool_call_id: nil,
      tool_name: nil,
      data: %{error: result}
    }

    {agent, _directives} =
      ChainOfDraftStrategy.cmd(
        agent,
        [%Jido.Instruction{action: :cod_worker_event, params: %{request_id: request_id, event: failed_event}}],
        %{}
      )

    agent
  end
end
