defmodule Jido.AI.Contract.AgentExtensionTest do
  use Covenant.Case, component: "jido_ai.agent_authoring", async: true

  alias Jido.AI.Agent.Extension
  alias Jido.AI.Reasoning.ReAct
  alias Jido.AITest.Tools.Add
  alias Jido.Authoring.Registry

  @tag obligation: ["jido_ai.agent_authoring.I1", "jido_ai.agent_authoring.I3"]
  test "the extension normalizes one route and rejects invalid provider data" do
    assert Extension.authoring_imports() == [Jido.AI.Agent.DSL]
    assert Extension.runtime_support() == Jido.AI.Toolset

    assert {:ok, normalized} =
             Extension.normalize(%{reasoning: ReAct, defaults: %{model: "contract:model"}, tools: [Add]})

    assert normalized == %{reasoning: ReAct, defaults: %{model: "contract:model"}, tools: [Add]}

    assert [route] = Extension.derive_routes(normalized)
    assert route.path == "jido.ai.request"
    assert route.handler == %{kind: :flow, target: ReAct}
    assert route.defaults.model == "contract:model"

    assert {:error, %{code: :invalid_reasoning}} = Extension.normalize(%{reasoning: String})
    assert {:error, %{code: :reserved_default}} = Extension.normalize(%{reasoning: ReAct, defaults: %{input: "bad"}})
    assert {:error, %{code: :invalid_defaults}} = Extension.normalize(%{reasoning: ReAct, defaults: []})

    assert {:error, %{code: :invalid_value, path: [:defaults, :model]}} =
             Extension.normalize(%{reasoning: ReAct, defaults: %{model: %{}}})

    assert {:error, %{code: :invalid_tools}} = Extension.normalize(%{reasoning: ReAct, tools: [:invalid]})
  end

  @tag obligation: ["jido_ai.agent_authoring.I1", "jido_ai.agent_authoring.I2"]
  test "the extension lowers either DSL declarations or provider data" do
    reasoning = %Extension.Reasoning{target: ReAct, defaults: %{model: "contract:model"}}
    tool = %Extension.Tool{target: Add}

    dsl = %{
      [:__ai__] => %{entities: [reasoning]},
      [:__ai__, :__tools__] => %{entities: [tool]}
    }

    assert {:ok, %{reasoning: ReAct, tools: [Add]}} = Extension.lower(dsl, %{})
    assert {:error, %{code: :ambiguous_ai}} = Extension.lower(dsl, %{reasoning: ReAct})

    assert {:ok, %{reasoning: ReAct, defaults: %{model: "provider:model"}}} =
             Extension.lower(%{}, %{reasoning: ReAct, defaults: %{model: "provider:model"}})

    assert {:error, %{code: :reasoning_count}} = Extension.lower(%{}, %{})

    assert {:error, %{code: :reasoning_count}} =
             Extension.lower(%{[:__ai__] => %{entities: [reasoning, reasoning]}}, %{})
  end

  @tag obligation: "jido_ai.agent_authoring.I4"
  test "extension authoring data round-trips and returns located codec errors" do
    registry = Registry.new!(%{{"contract/reasoning", 1} => {:flow, ReAct}, {"contract/add", 1} => {:action, Add}})
    data = %{reasoning: ReAct, defaults: %{model: "contract:model"}, tools: [Add]}

    assert {:ok,
            %{
              "reasoning" => %{"id" => "contract/reasoning", "vsn" => 1},
              "config" => %{"model" => "contract:model"},
              "tools" => [%{"id" => "contract/add", "vsn" => 1}]
            } = document} = Extension.encode_authoring_data(data, registry)

    assert {:ok, ^data} = Extension.decode_authoring_data(document, registry)
    assert {:error, %{code: :invalid_document, path: []}} = Extension.decode_authoring_data(:invalid, registry)

    assert {:error, %{code: :invalid_document, path: []}} =
             Extension.decode_authoring_data(%{"reasoning" => %{}}, registry)

    assert {:error, %{code: :reference, path: ["reasoning", "id"]}} =
             Extension.decode_authoring_data(%{document | "reasoning" => %{}}, registry)

    assert {:error, %{code: :invalid_tools, path: ["tools"]}} =
             Extension.decode_authoring_data(%{document | "tools" => :invalid}, registry)

    assert {:error, %{code: :reference, path: ["tools", 0, "id"]}} =
             Extension.decode_authoring_data(%{document | "tools" => [%{}]}, registry)

    assert {:error, _error} = Extension.encode_authoring_data(%{data | reasoning: String}, registry)

    registry_without_tool = Registry.new!(%{{"contract/reasoning", 1} => {:flow, ReAct}})
    assert {:error, %Registry.Error{}} = Extension.encode_authoring_data(data, registry_without_tool)

    assert {:error, %{code: :invalid_value, path: ["config", "model"]}} =
             Extension.decode_authoring_data(%{document | "config" => %{"model" => %{}}}, registry)

    invalid_tool_registry =
      Registry.new!(%{
        {"contract/reasoning", 1} => {:flow, ReAct},
        {"contract/invalid-tool", 1} => {:action, String}
      })

    invalid_tool_document = %{document | "tools" => [%{"id" => "contract/invalid-tool", "vsn" => 1}]}

    assert {:error, %{code: :invalid_tools, path: ["tools"]}} =
             Extension.decode_authoring_data(invalid_tool_document, invalid_tool_registry)
  end
end
