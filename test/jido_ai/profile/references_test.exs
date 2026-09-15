defmodule Jido.AI.Profile.ReferencesTest do
  use ExUnit.Case, async: false

  alias Jido.AI.Error.Validation.Invalid
  alias Jido.AI.Profile
  alias Jido.Codec.Registry

  defmodule Action do
    use Jido.Action, name: "reference_action", schema: Zoi.object(%{})

    @impl Jido.Action
    def run(_params, _context), do: raise("Profile construction must not run Actions")
  end

  defmodule ToolFlow do
    use Jido.Flow, name: "reference_flow"

    flow do
      step("tool", action: Action, params: %{})
      output(result("tool"))
    end
  end

  defmodule Control do
    def check(_value, _context), do: raise("Profile construction must not run controls")
  end

  defmodule Router do
    def route(_request, _context), do: raise("Profile construction must not route models")
  end

  defp attrs(overrides \\ %{}) do
    Map.merge(%{id: :assistant, model: :capable, result: %{into: :answer}}, overrides)
  end

  defp registries do
    %{
      actions: %{"action" => Action},
      flows: %{"flow" => ToolFlow},
      schemas: %{"schema" => Zoi.object(%{answer: Zoi.string()})},
      controls: %{"control" => Control},
      model_routers: %{"router" => Router}
    }
  end

  defp codec_registry do
    Registry.new!(%{
      "action" => {:action, Action},
      "old_action" => {:alias, "action"},
      "flow" => {:flow, ToolFlow}
    })
  end

  test "map registries resolve nested references and retain static policy" do
    registries = registries()

    input =
      attrs(%{
        instructions: %{action: "action"},
        models: %{entries: %{answer: :capable}, router: %{ref: "router", fallback: :answer}},
        tools: [%{ref: "action", as: :lookup, timeout: 321}, %{kind: :flow, ref: "flow", name: "plan"}],
        controls: %{
          input: [%{ref: "control"}],
          model: [%{ref: "control"}],
          operation: [%{ref: "control", when: %{tool: :lookup}}],
          output: [%{ref: "control"}],
          timeout: 1_234
        },
        result: %{into: :answer, schema: %{ref: "schema"}, repair_action: %{ref: "action"}, max_repairs: 1}
      })

    assert {:ok, profile} = Profile.new(input, registries: registries)
    assert profile.instructions == Action
    assert profile.models.answer.model == :capable
    assert profile.model_router == %{module: Router, fallback: :answer}
    assert Enum.map(profile.tools, &{&1.target, &1.name}) == [{Action, "lookup"}, {ToolFlow, "plan"}]
    assert hd(profile.tools).timeout == 321
    assert profile.controls.input == [Control]
    assert profile.controls.model == [Control]
    assert profile.controls.operation == [%{module: Control, when: %{"tool" => "lookup"}}]
    assert profile.controls.output == [Control]
    assert profile.controls.timeout == 1_234
    assert profile.result.schema == registries.schemas["schema"]
    assert profile.result.repair_action == Action
    assert profile.result.max_repairs == 1

    # Stored documents can use string keys at every reference boundary.
    assert {:ok, ^profile} = Profile.new(Profile.portable_data(input), registries: registries_keys(registries))
  end

  defp registries_keys(registries), do: Map.new(registries, fn {key, value} -> {Atom.to_string(key), value} end)

  test "Codec.Registry resolves Actions, aliases, and Flows without executing them" do
    input =
      attrs(%{
        instructions: %{"action" => "old_action"},
        tools: [%{ref: "action"}, %{"kind" => "flow", "ref" => "flow"}],
        result: [into: :answer, repair_action: %{ref: "old_action"}]
      })

    assert {:ok, profile} = Profile.new(input, registries: codec_registry())
    assert profile.instructions == Action
    assert Enum.map(profile.tools, & &1.target) == [Action, ToolFlow]
    assert profile.result.repair_action == Action

    assert {:ok, ^profile} =
             Profile.new(
               attrs(%{
                 instructions: Action,
                 tools: [Action, ToolFlow],
                 result: %{into: :answer, repair_action: Action}
               })
             )
  end

  test "tool sources stay separate and retain explicit then inline order" do
    input =
      attrs(%{
        tool_sources: [%{kind: :browser, name: :docs}],
        tools: [
          %{ref: "action"},
          %{"kind" => "mcp_tools", "endpoint" => "offline", "discover" => true},
          %{kind: :flow, ref: "flow"},
          %{kind: :catalog, ref: "catalog"}
        ]
      })

    assert {:ok, profile} = Profile.new(input, registries: Map.put(registries(), :catalogs, %{"catalog" => Router}))
    assert Enum.map(profile.tools, & &1.target) == [Action, ToolFlow]

    assert Enum.map(profile.tool_sources, &{&1.kind, &1.ref}) == [
             browser: "docs",
             mcp_tools: "offline",
             catalog: Router
           ]

    assert Enum.at(profile.tool_sources, 1).discover
  end

  test "Flow values work directly and through either registry form" do
    flow = ToolFlow.flow()
    assert {:ok, profile} = Profile.new(attrs(%{tools: [flow]}))
    assert hd(profile.tools).target == flow

    for registry <- [%{flows: %{"flow" => flow}}, Registry.new!(%{"flow" => {:flow, flow}})] do
      assert {:ok, ^profile} = Profile.new(attrs(%{tools: [%{kind: :flow, ref: "flow"}]}), registries: registry)
    end
  end

  test "missing map references retain their exact path and message" do
    for {kind, input} <- reference_inputs(), registry <- [nil, %{}, registries_keys(%{kind => %{}})] do
      assert_invalid(Profile.new(input, registries: registry), "registries.#{kind}", ~s(Unknown reference "missing"))
    end
  end

  test "malformed map registries retain their exact path and message" do
    for {kind, input} <- reference_inputs(), key <- [kind, Atom.to_string(kind)] do
      assert_invalid(Profile.new(input, registries: %{key => []}), "registries.#{kind}", "Expected a reference map")
    end
  end

  test "Codec.Registry errors pass through for missing and mismatched executable references" do
    registry = codec_registry()

    for {ref, kind, input} <- [
          {"missing", :action, attrs(%{instructions: %{action: "missing"}})},
          {"flow", :action, attrs(%{tools: [%{ref: "flow"}]})},
          {"action", :flow, attrs(%{tools: [%{kind: :flow, ref: "action"}]})},
          {"missing", :action, attrs(%{result: %{into: :answer, repair_action: %{ref: "missing"}}})}
        ] do
      {:error, expected} = Registry.resolve(registry, ref, kind)
      assert {:error, actual} = Profile.new(input, registries: registry)
      assert actual.__struct__ == expected.__struct__
      assert Exception.message(actual) == Exception.message(expected)
      assert actual.details == expected.details
    end
  end

  test "Codec.Registry keeps the unsupported schema, router, and control errors" do
    for {kind, input} <- reference_inputs(), kind in [:schemas, :model_routers, :controls] do
      assert_invalid(
        Profile.new(input, registries: codec_registry()),
        "registries",
        "This Registry does not contain #{kind}"
      )
    end
  end

  test "reference field validation rejects unknown and conflicting fields" do
    for {input, path, message} <- [
          {attrs(%{tools: [%{ref: "action", extra: true}]}), "tools", "Unknown field :extra"},
          {attrs(%{tools: [%{:ref => "action", "ref" => "action"}]}), "tools", "Conflicting field :ref"},
          {attrs(%{result: %{into: :answer, extra: true}}), "result", "Unknown field :extra"},
          {attrs(%{controls: %{extra: []}}), "controls", "Unknown field :extra"},
          {attrs(%{controls: %{:input => [], "input" => []}}), "controls", "Conflicting field :input"}
        ] do
      assert_invalid(Profile.new(input, registries: registries()), path, message)
    end

    assert_invalid(
      Profile.new(attrs(%{tools: [%{ref: "missing", extra: true}]}), registries: registries()),
      "registries.actions",
      ~s(Unknown reference "missing")
    )
  end

  test "malformed input containers keep their validation errors" do
    for {input, path, message} <- [
          {attrs(%{tools: :bad}), "tools", "Expected a tool list"},
          {attrs(%{tool_sources: :bad}), "tool_sources", "Expected a tool-source list"},
          {attrs(%{controls: [input: [], input: []]}), "profile", "Expected unique keyword fields"},
          {attrs(%{controls: [:input]}), "profile", "Expected unique keyword fields"},
          {attrs(%{controls: %URI{}}), "profile", "Expected a map or keyword list"}
        ] do
      assert_invalid(Profile.new(input), path, message)
    end
  end

  test "resolved values still pass through canonical policy validation" do
    assert_invalid(
      Profile.new(attrs(%{instructions: %{action: "bad"}}), registries: %{actions: %{"bad" => String}}),
      "instructions",
      "Expected text or an Action module"
    )

    assert_invalid(
      Profile.new(attrs(%{controls: %{input: [%{ref: "bad"}]}}), registries: %{controls: %{"bad" => String}}),
      "controls",
      "String must export check/2"
    )
  end

  test "omitted instructions retain configured defaults while nil and empty text override them" do
    previous = Application.fetch_env(:jido_ai, :agent_defaults)
    Application.put_env(:jido_ai, :agent_defaults, %{instructions: "Configured", model: :fast})

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:jido_ai, :agent_defaults, value)
        :error -> Application.delete_env(:jido_ai, :agent_defaults)
      end
    end)

    assert {:ok, profile} = Profile.new(Map.delete(attrs(), :model))
    assert profile.instructions == "Configured"
    assert profile.models.default.model == :fast

    for instructions <- [nil, ""] do
      assert {:ok, profile} = Profile.new(attrs(%{instructions: instructions}))
      assert profile.instructions == instructions
      assert profile.models.default.model == :capable
    end
  end

  defp reference_inputs do
    [
      actions: attrs(%{instructions: %{action: "missing"}}),
      actions: attrs(%{tools: [%{ref: "missing"}]}),
      flows: attrs(%{tools: [%{kind: :flow, ref: "missing"}]}),
      schemas: attrs(%{result: %{into: :answer, schema: %{ref: "missing"}}}),
      actions: attrs(%{result: %{into: :answer, repair_action: %{ref: "missing"}}}),
      model_routers: attrs(%{models: %{entries: %{default: :capable}, router: %{ref: "missing"}}}),
      controls: attrs(%{controls: [input: [%{ref: "missing"}]]})
    ]
  end

  defp assert_invalid(result, field, message) do
    assert {:error, %Invalid{field: ^field, message: actual}} = result
    assert actual == "#{field}: #{message}"
  end
end
