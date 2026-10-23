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

  defmodule FixedReasoning.Answer do
    use Jido.Action,
      name: "fixed_reasoning_answer",
      description: "Return one fixed reasoning result"

    @impl Jido.Action
    def run(%{request: request}, _context) do
      {:ok,
       %{
         output: "Custom: #{request.input}",
         usage: Jido.AI.Reasoning.State.usage(request),
         trace: [%{type: :custom_reasoning}]
       }}
    end
  end

  defmodule FixedReasoning do
    use Jido.Flow,
      name: "fixed_reasoning",
      description: "Return a fixed answer without a model call"

    flow do
      step "answer", action: FixedReasoning.Answer, params: input()
      output result("answer")
    end
  end

  defmodule CustomReasoningAssistant do
    use Jido.AI.Agent, name: "custom_reasoning_assistant"

    ai do
      model "openai:gpt-4o-mini"
      reasoning FixedReasoning
    end
  end

  defmodule InlineReasoningAssistant do
    use Jido.AI.Agent, name: "inline_reasoning_assistant"

    alias Jido.AI.PluginTest.FixedReasoning.Answer

    ai do
      model "openai:gpt-4o-mini"

      reasoning do
        step "answer", action: Answer, params: input()
        output result("answer")
      end
    end
  end

  test "an Agent declares its basic AI configuration" do
    assert Jido.AI.Plugin.config(Assistant) == %{
             model: :fast,
             instructions: "Reply in one short sentence.",
             reasoning: Jido.AI.Flow.ReAct,
             tools: [],
             controls: Jido.AI.Plugin.default_controls()
           }
  end

  test "the Plugin prepares the current AI configuration for a route Action" do
    config = Jido.AI.Plugin.config(Assistant)
    assert Jido.AI.Plugin.prepare(nil, Map.to_list(config)) == {:ok, config}
    assert Jido.AI.Plugin.prepare(nil, []) == {:error, :missing_ai_config}
  end

  test "an Agent can replace the default ReAct reasoning Flow" do
    assert Jido.AI.Plugin.config(CustomReasoningAssistant).reasoning == FixedReasoning
    assert CustomReasoningAssistant.generate("hello") == {:ok, "Custom: hello"}
  end

  test "an Agent can declare its reasoning Flow inline" do
    reasoning = Jido.AI.Plugin.config(InlineReasoningAssistant).reasoning
    path = [host: Jido.AI.Plugin, declaration: :reasoning, role: :flow]

    assert reasoning == Jido.Flow.Inline.target!(InlineReasoningAssistant, path)
    assert reasoning.__jido_inline_flow__() == {InlineReasoningAssistant, path}
    assert reasoning.__jido_authoring_kind__() == :flow
    assert reasoning.name() == "inline_reasoning_assistant_reasoning"
    assert InlineReasoningAssistant.generate("hello") == {:ok, "Custom: hello"}
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
             input: PermitInput,
             output: CheckOutput
           }
  end

  test "a controls block accepts only one input and one output definition" do
    for {stage, action} <- [input: PermitInput, output: CheckOutput] do
      module = "Jido.AI.PluginTest.Duplicate#{stage |> Atom.to_string() |> Macro.camelize()}Control"

      source = """
      defmodule #{module} do
        use Jido.AI.Agent, name: "duplicate_#{stage}_control"

        ai do
          model :fast

          controls do
            #{stage} #{inspect(action)}
            #{stage} #{inspect(action)}
          end
        end
      end
      """

      assert_raise Spark.Error.DslError, ~r/Expected a single #{stage}/, fn ->
        Code.compile_string(source)
      end
    end
  end

  test "map configuration rejects control lists" do
    assert {:error, %Jido.Agent.Error{path: [:controls, :input]}} =
             Jido.AI.Plugin.normalize(%{
               model: :fast,
               controls: %{input: [PermitInput]}
             })
  end

  defmodule InlineControlsAssistant do
    use Jido.AI.Agent, name: "inline_controls_assistant"

    ai do
      model :fast

      controls do
        input %{input: input},
          name: "inline_input_control",
          schema: Zoi.object(%{input: Zoi.string()}),
          context: context do
          if authorized?(input, context),
            do: {:ok, %{allowed: true}},
            else: {:error, :not_authorized}
        end

        output %{output: output},
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

    input = controls.input
    output = controls.output
    assert input.__jido_authoring_kind__() == :action
    assert output.__jido_authoring_kind__() == :action
    assert function_exported?(input, :__jido_inline_action__, 0)
    assert function_exported?(output, :__jido_inline_action__, 0)
    assert Jido.AI.Controls.run(input, :input, "request", %{authorized: true}) == :ok
    assert Jido.AI.Controls.run(output, :output, "answer", %{}) == :ok
  end
end
