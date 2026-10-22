defmodule JidoAI.Examples.CoreCompositionTest do
  use ExUnit.Case, async: false

  import Mimic

  alias JidoAI.Examples.CoreComposition.{Agent, Audit}

  @moduletag :example

  setup :verify_on_exit!

  setup do
    original = Application.get_env(:jido_ai, :model_aliases)
    Application.put_env(:jido_ai, :model_aliases, %{fast: "openai:gpt-4o-mini"})
    on_exit(fn -> restore_aliases(original) end)
  end

  test "AI configuration composes with core state and another extension" do
    providers = Enum.map(Agent.definition().extensions, & &1.provider)
    assert providers == [Jido.AI.Plugin, Audit]

    instance = Agent.instantiate!(id: "core-example", state: %{customer_id: "customer-1"})
    original_state = instance.state

    expect(ReqLLM, :generate_text, fn model, context, _options ->
      {:ok,
       %ReqLLM.Response{
         id: "core-example",
         model: model,
         context: context,
         message: ReqLLM.Context.assistant("Hello")
       }}
    end)

    assert Jido.AI.generate(instance, "Hello") == {:ok, "Hello"}
    assert instance.state == original_state
    assert instance.state == %{customer_id: "customer-1", request_count: 0}
  end

  defp restore_aliases(nil), do: Application.delete_env(:jido_ai, :model_aliases)
  defp restore_aliases(aliases), do: Application.put_env(:jido_ai, :model_aliases, aliases)
end
