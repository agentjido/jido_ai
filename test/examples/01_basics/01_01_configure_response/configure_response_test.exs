defmodule JidoAI.Examples.ConfigureResponseTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Plugin
  alias JidoAI.Examples.ConfigureResponse.Agent

  @moduletag :example

  test "the Agent keeps its normalized AI response configuration" do
    expected = %{
      model: "openai:gpt-4o-mini",
      instructions: "Reply in one short sentence."
    }

    definition = Agent.definition()
    instance = Agent.instantiate!(id: "configure-response-example")

    assert Jido.Agent.definition?(definition)
    assert Jido.Agent.instance?(instance)
    assert Plugin.response(definition) == expected
    assert Plugin.response(instance) == expected
  end
end
