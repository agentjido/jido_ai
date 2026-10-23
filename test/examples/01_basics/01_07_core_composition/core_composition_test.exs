defmodule JidoAI.Examples.CoreCompositionTest do
  use Jido.AI.Test.ReqLLMCase, async: false

  alias JidoAI.Examples.CoreComposition.{Agent, Audit}

  @moduletag :example

  test "AI configuration composes with core state and another extension" do
    providers = Enum.map(Agent.definition().extensions, & &1.provider)
    assert providers == [Jido.AI.Plugin, Audit]

    instance = Agent.instantiate!(id: "core-example", state: %{customer_id: "customer-1"})
    original_state = instance.state

    expect(ReqLLM, :generate_text, fn model, context, _options ->
      {:ok, text_response(model, context, "Hello", id: "core-example")}
    end)

    assert Jido.AI.generate(instance, "Hello") == {:ok, "Hello"}
    assert instance.state == original_state
    assert instance.state == %{customer_id: "customer-1", request_count: 0}
  end
end
