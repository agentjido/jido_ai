defmodule JidoAI.Examples.BasicAgentTest do
  use Jido.AI.Test.ReqLLMCase, async: false

  alias Jido.AI.Plugin
  alias JidoAI.Examples.BasicAgent.Agent

  @moduletag :example

  test "the Agent keeps its normalized AI configuration" do
    expected = %{
      model: :fast,
      instructions: "Reply in one short sentence.",
      reasoning: Jido.AI.Flow.ReAct,
      tools: [],
      controls: Plugin.default_controls()
    }

    definition = Agent.definition()
    instance = Agent.instantiate!(id: "basic-ai-agent-example")

    assert Jido.Agent.definition?(definition)
    assert Jido.Agent.instance?(instance)
    assert Plugin.config(definition) == expected
    assert Plugin.config(instance) == expected
  end

  test "the Agent returns one text answer" do
    expect(ReqLLM, :generate_text, fn model, context, options ->
      assert model == "openai:gpt-4o-mini"
      assert options[:receive_timeout] in 1..60_000

      assert [system, user] = ReqLLM.Context.to_list(context)
      assert %{role: :system, content: [%{text: "Reply in one short sentence."}]} = system
      assert %{role: :user, content: [%{text: "Are you ready?"}]} = user

      {:ok, text_response(model, context, "Ready", id: "one-answer-example")}
    end)

    assert Agent.generate("Are you ready?") == {:ok, "Ready"}
  end
end
