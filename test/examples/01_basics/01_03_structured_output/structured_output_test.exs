defmodule JidoAI.Examples.StructuredOutputTest do
  use ExUnit.Case, async: false

  import Mimic

  alias Jido.Agent.Directive.Emit
  alias JidoAI.Examples.StructuredOutput.{Agent, Ask}

  @moduletag :example

  setup :verify_on_exit!

  setup do
    original = Application.get_env(:jido_ai, :model_aliases)
    Application.put_env(:jido_ai, :model_aliases, %{fast: "openai:gpt-4o-mini"})
    on_exit(fn -> restore_aliases(original) end)
  end

  test "the route shapes and emits the structured reply" do
    expected = %{answer: "Ready", confidence: 0.9}

    expect(ReqLLM, :generate_text, fn model, context, options ->
      assert model == "openai:gpt-4o-mini"
      assert %ReqLLM.Output{type: :object, schema: schema} = options[:output]
      assert schema == Ask.__signal_action__().output.schema
      assert options[:receive_timeout] in 1..60_000

      {:ok,
       %ReqLLM.Response{
         id: "structured-example",
         model: model,
         context: context,
         message: ReqLLM.Context.assistant(""),
         object: %{"answer" => "Ready", "confidence" => 0.9}
       }}
    end)

    agent = Agent.instantiate!(id: "structured-output")
    request = Agent.ask_signal!(%{question: "Are we ready?"})

    assert {:ok, ^agent, [%Emit{signal: reply}]} = Agent.cmd(agent, request)
    assert reply.type == "examples.structured_output.answered"
    assert reply.data == expected
    assert Jido.Signal.get_context(reply, "jidocausationid") == request.id
  end

  defp restore_aliases(nil), do: Application.delete_env(:jido_ai, :model_aliases)
  defp restore_aliases(aliases), do: Application.put_env(:jido_ai, :model_aliases, aliases)
end
