defmodule Jido.AI.Authoring.ContentPermissionsTest do
  use ExUnit.Case, async: true

  defmodule ObservedAgent do
    use Jido.AI.Agent, name: "observed_agent"

    agent do
      schema Zoi.object(%{reply: Zoi.string() |> Zoi.default("")})

      ai :assistant do
        model :fast

        observability do
          stream_content true
          store_content false
          stream_reasoning false
          store_reasoning true
          diagnostics_content true
        end

        result into: :reply
      end
    end
  end

  test "DSL and Profile retain independent content permissions" do
    expected = %{
      stream_content: true,
      store_content: false,
      stream_reasoning: false,
      store_reasoning: true,
      diagnostics_content: true
    }

    assert Jido.AI.Agent.profile(ObservedAgent, :assistant).observability == expected
    attrs = %{id: :assistant, model: :fast, result: %{into: :reply}, observability: expected}
    assert Jido.AI.Profile.new!(attrs).observability == expected

    for key <- Map.keys(expected) do
      assert {:error, _} = Jido.AI.Profile.new(%{attrs | observability: %{key => "true"}})
    end
  end

  test "standalone content permissions default off and require explicit options" do
    config = Jido.AI.Reasoning.ReAct.Config.new(model: :fast)

    for key <- [:stream_content, :store_content, :stream_reasoning, :store_reasoning, :diagnostics_content],
        do: assert(config.observability[key] == false)

    config = Jido.AI.Reasoning.ReAct.Config.new(model: :fast, stream_content: true, store_reasoning: true)
    assert config.observability.stream_content and config.observability.store_reasoning
    refute config.observability.store_content or config.observability.stream_reasoning
  end
end
