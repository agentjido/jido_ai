defmodule Jido.AI.PluginTest do
  use ExUnit.Case, async: true

  defmodule Multiply do
    use Jido.Action,
      name: "multiply",
      description: "Multiply two integers",
      schema: Zoi.object(%{left: Zoi.integer(), right: Zoi.integer()})

    @impl Jido.Action
    def run(%{left: left, right: right}, _context), do: {:ok, %{product: left * right}}
  end

  defmodule MultiplyFlow do
    use Jido.Flow,
      name: "multiply_flow",
      description: "Multiply two integers in a Flow",
      schema: Zoi.object(%{left: Zoi.integer(), right: Zoi.integer()})

    flow do
      step "multiply", action: Multiply, params: input()
      output result("multiply")
    end
  end

  defmodule PermitInput do
    use Jido.Action,
      name: "permit_input",
      description: "Permit one input",
      schema: Zoi.object(%{input: Zoi.string()})

    @impl Jido.Action
    def run(_params, _context), do: {:ok, %{allowed: true}}
  end

  defmodule CheckOutput do
    use Jido.Action,
      name: "check_output",
      description: "Check one output",
      schema: Zoi.object(%{output: Zoi.string()})

    @impl Jido.Action
    def run(_params, _context), do: {:ok, %{allowed: true}}
  end

  defmodule ActionLookalike do
    def __jido_authoring_kind__, do: :action
    def name, do: "action_lookalike"
    def description, do: "Has callbacks but is not a Jido Action"
    def schema, do: []
    def validate_params(params), do: {:ok, params}
    def validate_output(output), do: {:ok, output}
    def run(_params, _context), do: {:ok, %{}}
  end

  defmodule Assistant do
    use Jido.AI.Agent, name: "assistant"

    ai do
      model :fast
      instructions "Reply in one short sentence."
    end
  end

  test "an Agent declares its basic AI configuration" do
    assert Jido.AI.Plugin.config(Assistant) == %{
             model: :fast,
             instructions: "Reply in one short sentence.",
             tools: [],
             controls: Jido.AI.Plugin.default_controls()
           }
  end

  test "the Plugin prepares the current AI configuration for a route Action" do
    config = Jido.AI.Plugin.config(Assistant)
    assert Jido.AI.Plugin.prepare(nil, Map.to_list(config)) == {:ok, config}
    assert Jido.AI.Plugin.prepare(nil, []) == {:error, :missing_ai_config}
  end

  test "the AI Plugin publishes the shared Jido authoring manifest" do
    assert %{
             id: "jido.ai",
             kind: :plugin,
             target: Jido.AI.Plugin,
             vsn: 1
           } = Jido.AI.Plugin.__jido_authoring__()
  end

  test "executable validation uses the Jido Instruction contract" do
    assert {:error,
            %Jido.Agent.Error{
              code: :invalid_executable,
              path: [:tools, 0]
            }} =
             Jido.AI.Plugin.normalize(%{
               model: :fast,
               tools: [%{kind: :action, target: ActionLookalike}]
             })
  end

  defmodule ConfiguredAssistant do
    use Jido.AI.Agent, name: "configured_assistant"

    ai do
      model :fast

      tools do
        action Multiply, as: :calculate, timeout: 1_000
        flow MultiplyFlow
      end

      controls do
        timeout 10_000
        max_iterations 2
        max_model_calls 3
        max_tool_calls 4
        input PermitInput
        output CheckOutput
      end
    end
  end

  test "tool and control blocks normalize Jido primitives" do
    config = Jido.AI.Plugin.config(ConfiguredAssistant)

    assert config.tools == [
             %{
               kind: :action,
               target: Multiply,
               name: "calculate",
               description: "Multiply two integers",
               timeout: 1_000
             },
             %{
               kind: :flow,
               target: MultiplyFlow,
               name: "multiply_flow",
               description: "Multiply two integers in a Flow",
               timeout: 5_000
             }
           ]

    assert config.controls == %{
             timeout: 10_000,
             max_iterations: 2,
             max_model_calls: 3,
             max_tool_calls: 4,
             input: [PermitInput],
             output: [CheckOutput]
           }
  end

  defmodule InlineControlsAssistant do
    use Jido.AI.Agent, name: "inline_controls_assistant"

    ai do
      model :fast

      controls do
        input_action %{input: input},
          name: "inline_input_control",
          schema: Zoi.object(%{input: Zoi.string()}),
          context: context do
          if authorized?(input, context),
            do: {:ok, %{allowed: true}},
            else: {:error, :not_authorized}
        end

        output_action %{output: output},
          name: "inline_output_control",
          schema: Zoi.object(%{output: Zoi.string()}) do
          {:ok, %{length: String.length(output)}}
        end
      end
    end

    defp authorized?(input, context), do: input != "" and context[:authorized] == true
  end

  test "inline controls compile to ordinary Jido Actions" do
    controls = Jido.AI.Plugin.config(InlineControlsAssistant).controls

    assert [input] = controls.input
    assert [output] = controls.output
    assert input.__jido_authoring_kind__() == :action
    assert output.__jido_authoring_kind__() == :action
    assert function_exported?(input, :__jido_inline_action__, 0)
    assert function_exported?(output, :__jido_inline_action__, 0)
    assert Jido.AI.Controls.run([input], :input, "request", %{authorized: true}) == :ok
    assert Jido.AI.Controls.run([output], :output, "answer", %{}) == :ok
  end
end
