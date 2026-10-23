defmodule JidoAI.Examples.BasicAgentTest do
  use ExUnit.Case, async: false

  import Mimic

  alias Jido.AI.Plugin
  alias JidoAI.Examples.BasicAgent.Agent

  @moduletag :example

  setup :verify_on_exit!

  setup do
    original = Application.get_env(:jido_ai, :model_aliases)
    Application.put_env(:jido_ai, :model_aliases, %{fast: "openai:gpt-4o-mini"})
    on_exit(fn -> restore_aliases(original) end)
  end

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

      {:ok,
       %ReqLLM.Response{
         id: "one-answer-example",
         model: model,
         context: context,
         message: ReqLLM.Context.assistant("Ready")
       }}
    end)

    assert Agent.generate("Are you ready?") == {:ok, "Ready"}
  end

  defp restore_aliases(nil), do: Application.delete_env(:jido_ai, :model_aliases)
  defp restore_aliases(aliases), do: Application.put_env(:jido_ai, :model_aliases, aliases)
end
