defmodule Jido.AI.CoTAgentTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Request
  alias Jido.AI.Reasoning.ChainOfThought.Strategy, as: ChainOfThought

  defmodule TestCoTAgent do
    use Jido.AI.CoTAgent,
      name: "test_cot_agent",
      model: "test:model"
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

  describe "module creation" do
    test "defines expected helper API" do
      assert function_exported?(TestCoTAgent, :think, 2)
      assert function_exported?(TestCoTAgent, :think_sync, 2)
      assert function_exported?(TestCoTAgent, :await, 1)
      assert function_exported?(TestCoTAgent, :strategy_opts, 0)
    end
  end

  describe "strategy configuration" do
    test "uses ChainOfThought strategy" do
      assert TestCoTAgent.strategy() == ChainOfThought
    end

    test "uses expected defaults when not provided" do
      opts = DefaultCoTAgent.strategy_opts()

      assert opts[:model] == "anthropic:claude-haiku-4-5"
      refute Keyword.has_key?(opts, :system_prompt)
    end

    test "passes custom model and system_prompt options to strategy" do
      opts = PromptedCoTAgent.strategy_opts()

      assert opts[:model] == "openai:gpt-4"
      assert opts[:system_prompt] == "Think in clear numbered steps."
    end
  end

  describe "request lifecycle hooks" do
    test "on_before_cmd marks request as failed on cot_request_error" do
      agent = TestCoTAgent.new()
      agent = Request.start_request(agent, "req_1", "query")

      {:ok, agent, _action} =
        TestCoTAgent.on_before_cmd(
          agent,
          {:cot_request_error, %{request_id: "req_1", reason: :busy, message: "busy"}}
        )

      assert get_in(agent.state, [:requests, "req_1", :status]) == :failed
      assert get_in(agent.state, [:requests, "req_1", :error]) == {:rejected, :busy, "busy"}
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
