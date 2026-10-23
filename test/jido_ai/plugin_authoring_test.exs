defmodule Jido.AI.Plugin.AuthoringTest do
  use ExUnit.Case, async: false

  alias Jido.Authoring.Registry

  defmodule Add do
    use Jido.Action,
      name: "json_agent_add",
      description: "Add two integers",
      schema: Zoi.object(%{left: Zoi.integer(), right: Zoi.integer()})

    def run(%{left: left, right: right}, _context), do: {:ok, %{sum: left + right}}
  end

  defmodule AddFlow do
    use Jido.Flow,
      name: "json_agent_add_flow",
      description: "Add two integers through a Flow",
      schema: Zoi.object(%{left: Zoi.integer(), right: Zoi.integer()})

    flow do
      step "add", action: Add, params: input()
      output result("add")
    end
  end

  defmodule Permit do
    use Jido.Action,
      name: "json_agent_permit",
      schema: Zoi.object(%{input: Zoi.string()})

    def run(_params, _context), do: {:ok, %{allowed: true}}
  end

  defmodule CustomReasoning.Answer do
    use Jido.Action, name: "json_agent_custom_reasoning_answer"

    def run(%{request: request}, _context) do
      {:ok,
       %{
         output: request.input,
         usage: Jido.AI.Reasoning.State.usage(request),
         trace: [%{type: :custom_reasoning}]
       }}
    end
  end

  defmodule CustomReasoning do
    use Jido.Flow,
      id: "tests/flows/json-agent-custom-reasoning",
      name: "json_agent_custom_reasoning"

    flow do
      step "answer", action: CustomReasoning.Answer, params: input()
      output result("answer")
    end
  end

  defmodule Assistant do
    use Jido.AI.Agent,
      id: "tests/agents/json-ai-assistant",
      name: "json_ai_assistant"

    ai do
      model :fast
      instructions "Use tools when needed."
      reasoning CustomReasoning

      tools do
        action Add, as: :add_numbers
        flow AddFlow
      end

      controls do
        timeout 15_000
        max_iterations 3
        max_model_calls 4
        max_tool_calls 5
        input Permit
      end
    end
  end

  setup do
    original = Application.get_env(:jido_ai, :model_aliases)
    Application.put_env(:jido_ai, :model_aliases, %{fast: "openai:gpt-4o-mini"})
    on_exit(fn -> restore_aliases(original) end)
  end

  test "an AI Agent definition round trips through Jido Authoring JSON" do
    definition = Assistant.definition()
    registry = registry()

    assert {:ok, json} =
             Jido.Authoring.encode_json(
               definition,
               registry: registry,
               codec: Jido.Agent.Codec
             )

    assert {:ok, imported} =
             Jido.Authoring.decode_json(
               json,
               registry: registry,
               codec: Jido.Agent.Codec
             )

    assert imported == definition
    assert Jido.AI.Plugin.config(imported) == Jido.AI.Plugin.config(Assistant)
    assert Jido.AI.Plugin.config(imported).reasoning == CustomReasoning

    document = Jason.decode!(json)
    [action, flow] = get_in(document, ["definition", "extensions", Access.at(0), "data", "tools"])

    assert action["target"] == %{"id" => "tests/actions/json-agent-add", "vsn" => 1}
    assert flow["target"] == %{"id" => "tests/flows/json-agent-add", "vsn" => 1}

    config = get_in(document, ["definition", "extensions", Access.at(0), "data"])

    assert config["reasoning"] == %{
             "kind" => "flow",
             "target" => %{"id" => "tests/flows/json-agent-custom-reasoning", "vsn" => 1}
           }

    refute Map.has_key?(config, "output")
  end

  test "an imported model alias must exist and does not create an atom" do
    assert {:ok, document} =
             Jido.Authoring.encode(
               Assistant,
               registry: registry(),
               codec: Jido.Agent.Codec
             )

    unknown = "untrusted_alias_#{System.unique_integer([:positive])}"

    invalid =
      put_in(
        document,
        ["definition", "extensions", Access.at(0), "data", "model", "value"],
        unknown
      )

    assert {:error, _issues} =
             Jido.Authoring.decode(invalid, registry: registry(), codec: Jido.Agent.Codec)

    assert_raise ArgumentError, fn -> String.to_existing_atom(unknown) end
  end

  defp registry do
    definition = Assistant.definition()

    Registry.new!(%{
      {"tests/agents/json-ai-assistant", 1} => {:agent, Assistant},
      {"tests/schemas/json-ai-assistant", 1} => {:schema, definition.schema},
      {"jido.ai", 1} => {:plugin, Jido.AI.Plugin},
      {"tests/actions/json-agent-add", 1} => {:action, Add},
      {"tests/flows/json-agent-add", 1} => {:flow, AddFlow},
      {"tests/flows/json-agent-custom-reasoning", 1} => {:flow, CustomReasoning},
      {"tests/actions/json-agent-permit", 1} => {:action, Permit}
    })
  end

  defp restore_aliases(nil), do: Application.delete_env(:jido_ai, :model_aliases)
  defp restore_aliases(aliases), do: Application.put_env(:jido_ai, :model_aliases, aliases)
end
