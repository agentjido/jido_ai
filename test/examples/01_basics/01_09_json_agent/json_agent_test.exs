defmodule JidoAI.Examples.JSONAgentTest do
  use ExUnit.Case, async: false

  import Mimic

  alias Jido.Agent.Directive.Emit
  alias JidoAI.Examples.JSONAgent, as: Example
  alias JidoAI.Examples.JSONAgent.Ask

  @moduletag :example

  setup :verify_on_exit!

  setup do
    original = Application.get_env(:jido_ai, :model_aliases)
    Application.put_env(:jido_ai, :model_aliases, %{fast: "openai:gpt-4o-mini"})
    on_exit(fn -> restore_aliases(original) end)
  end

  test "the saved JSON imports the complete AI definition" do
    assert {:ok, current_json} = Example.encode_json()
    assert Jason.decode!(Example.fixture_json()) == Jason.decode!(current_json)

    assert {:ok, imported} = Example.import()
    assert imported == Example.definition()

    config = Jido.AI.Plugin.config(imported)
    assert config.model == :fast
    assert Enum.map(config.tools, & &1.name) == ["add_numbers", "json_example_add_flow"]
    assert config.controls.input == [JidoAI.Examples.JSONAgent.Permit]
    refute Map.has_key?(config, :output)
  end

  test "the imported Agent routes and emits a structured response" do
    assert {:ok, imported} = Example.import()

    expect(ReqLLM, :generate_text, fn model, context, options ->
      assert model == "openai:gpt-4o-mini"
      assert Enum.map(options[:tools], & &1.name) == ["add_numbers", "json_example_add_flow"]
      assert %ReqLLM.Output{type: :object, schema: schema} = options[:output]
      assert schema == Ask.__signal_action__().output.schema

      {:ok,
       %ReqLLM.Response{
         id: "json-agent-example",
         model: model,
         context: context,
         message: ReqLLM.Context.assistant(""),
         object: %{"answer" => "Ready", "confidence" => 0.95}
       }}
    end)

    agent = Jido.Agent.instantiate!(imported, id: "imported-json-ai")
    request = Ask.new!(%{question: "Are you ready?"})

    assert {:ok, ^agent, [%Emit{signal: reply}]} = Jido.Agent.cmd(agent, request)
    assert reply.type == "examples.json_ai.answered"
    assert reply.data == %{answer: "Ready", confidence: 0.95}
    assert Jido.Signal.get_context(reply, "jidocausationid") == request.id
  end

  defp restore_aliases(nil), do: Application.delete_env(:jido_ai, :model_aliases)
  defp restore_aliases(aliases), do: Application.put_env(:jido_ai, :model_aliases, aliases)
end
