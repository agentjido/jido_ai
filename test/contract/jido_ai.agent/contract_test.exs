defmodule JidoAI.Contract.AgentContractTest do
  use Covenant.Case, component: "jido_ai.agent", async: false

  alias Jido.Authoring.Registry

  defmodule AuditExtension do
    use Jido.Agent.Extension, id: "tests/extensions/jido-ai-audit"
  end

  defmodule Multiply do
    use Jido.Action,
      name: "contract_multiply",
      description: "Multiply two integers",
      schema: Zoi.object(%{left: Zoi.integer(), right: Zoi.integer()})

    @impl Jido.Action
    def run(%{left: left, right: right}, _context), do: {:ok, %{product: left * right}}
  end

  defmodule MultiplyFlow do
    use Jido.Flow,
      name: "contract_multiply_flow",
      description: "Multiply two integers through a Flow",
      schema: Zoi.object(%{left: Zoi.integer(), right: Zoi.integer()})

    flow do
      step "multiply", action: Multiply, params: input()
      output result("multiply")
    end
  end

  defmodule PermitInput do
    use Jido.Action,
      name: "contract_permit_input",
      description: "Permit one AI request",
      schema: Zoi.object(%{input: Zoi.string()})

    @impl Jido.Action
    def run(_params, _context), do: {:ok, %{allowed: true}}
  end

  defmodule CheckOutput do
    use Jido.Action,
      name: "contract_check_output",
      description: "Check one AI result",
      schema: Zoi.object(%{output: Zoi.any()})

    @impl Jido.Action
    def run(_params, _context), do: {:ok, %{allowed: true}}
  end

  defmodule Ask do
    use Jido.SignalAction,
      name: "contract_ask",
      description: "Ask for one structured answer",
      vsn: 1,
      input: [
        type: "tests.jido_ai.ask",
        default_source: "/tests/jido-ai/client",
        schema: Zoi.object(%{question: Zoi.string()})
      ],
      output: [
        type: "tests.jido_ai.answered",
        default_source: "/tests/jido-ai",
        schema:
          Zoi.object(%{
            answer: Zoi.string(),
            confidence: Zoi.number() |> Zoi.min(0) |> Zoi.max(1)
          })
      ]

    @impl Jido.Action
    def run(_params, _context), do: {:ok, %{answer: "Ready", confidence: 1.0}}
  end

  defmodule ObservePrepared do
    use Jido.Action,
      name: "contract_observe_prepared",
      description: "Observe the prepared AI configuration",
      schema: Ask.schema()

    @impl Jido.Action
    def run(_params, context) do
      send(
        context.test_pid,
        {:prepared_ai, context.plugin_inputs[Jido.AI.Plugin].prepared, Map.take(context, [:ai, :config])}
      )

      {:ok, context.agent_state}
    end
  end

  defmodule ActionLookalike do
    def __jido_authoring_kind__, do: :action
    def name, do: "contract_action_lookalike"
    def description, do: "Not a Jido Action"
    def schema, do: Zoi.object(%{})
    def run(_params, _context), do: {:ok, %{}}
  end

  defmodule Assistant do
    use Jido.AI.Agent,
      id: "tests/agents/jido-ai-contract",
      name: "jido_ai_contract_agent",
      extensions: [AuditExtension, Jido.AI.Plugin]

    ai do
      model :fast
      instructions "Return a concise answer."

      tools do
        action Multiply, as: :multiply
        flow MultiplyFlow
      end

      controls do
        timeout 15_000
        max_iterations 3
        max_model_calls 4
        max_tool_calls 5
        input PermitInput
        output CheckOutput
      end
    end

    routes do
      signal_source "/tests/jido-ai"

      route Ask, ObservePrepared, as: :ask
    end
  end

  defmodule StatefulAssistant do
    use Jido.AI.Agent, name: "jido_ai_stateful_contract_agent"

    state do
      schema(
        Zoi.object(%{
          session: Jido.Session.schema(),
          tone: Zoi.string() |> Zoi.default("schema")
        })
      )
    end

    @impl Jido.Agent
    def initialize(state, _context) do
      {:ok,
       state
       |> Map.put_new_lazy(:session, &Jido.Session.new!/0)
       |> Map.put_new(:tone, "initialized")}
    end

    ai do
      model :fast
    end
  end

  @tag obligation: "jido_ai.agent.I1"
  test "the convenience macro adds one AI Plugin and preserves other extensions" do
    providers = Enum.map(Assistant.definition().extensions, & &1.provider)

    assert Enum.count(providers, &(&1 == Jido.AI.Plugin)) == 1
    assert Enum.count(providers, &(&1 == AuditExtension)) == 1
  end

  @tag obligation: "jido_ai.agent.I2"
  test "the AI block normalizes one small definition" do
    config = Jido.AI.Plugin.config(Assistant)

    assert config.model == :fast
    assert config.instructions == "Return a concise answer."

    assert Map.keys(config) |> Enum.sort() == [
             :controls,
             :instructions,
             :model,
             :reasoning,
             :tools
           ]

    assert config.reasoning == Jido.AI.Flow.ReAct

    assert Jido.AI.Plugin.default_controls() == %{
             timeout: 60_000,
             max_iterations: 8,
             max_model_calls: 12,
             max_tool_calls: 16,
             input: nil,
             output: nil
           }
  end

  @tag obligation: "jido_ai.agent.I3"
  test "tools and controls retain their Jido executable kinds" do
    config = Jido.AI.Plugin.config(Assistant)

    assert Enum.map(config.tools, &{&1.kind, &1.target}) == [
             {:action, Multiply},
             {:flow, MultiplyFlow}
           ]

    for tool <- config.tools do
      assert {:ok, instruction} = Jido.Instruction.resolve(tool.target)
      assert instruction.kind == tool.kind
    end

    for control <- [config.controls.input, config.controls.output] do
      assert {:ok, %{kind: :action}} = Jido.Instruction.resolve(control)
    end

    assert {:error, %Jido.Agent.Error{}} =
             Jido.AI.Plugin.normalize(%{
               model: :fast,
               tools: [%{kind: :action, target: ActionLookalike}]
             })

    assert {:error, %Jido.Agent.Error{}} =
             Jido.AI.Plugin.normalize(%{
               model: :fast,
               controls: %{input: MultiplyFlow}
             })
  end

  @tag obligation: "jido_ai.agent.I4"
  test "Plugin preparation gives the route Action the normalized AI configuration" do
    config = Jido.AI.Plugin.config(Assistant)
    agent = Assistant.instantiate!(id: "contract-prepared-input")
    request = Ask.new!(%{question: "Are you ready?"})

    assert {:ok, result_agent, []} =
             Assistant.cmd(agent, request, context: %{test_pid: self()})

    assert_receive {:prepared_ai, ^config, %{}}
    assert result_agent.state == %{}
  end

  @tag obligation: ["jido_ai.agent.I5", "jido_ai.agent.I6"]
  test "registered JSON references round-trip the same Agent definition" do
    registry = registry()

    assert {:ok, json} =
             Jido.Authoring.encode_json(
               Assistant.definition(),
               registry: registry,
               codec: Jido.Agent.Codec
             )

    assert {:ok, imported} =
             Jido.Authoring.decode_json(
               json,
               registry: registry,
               codec: Jido.Agent.Codec
             )

    assert imported == Assistant.definition()

    document = Jason.decode!(json)
    definition = document["definition"]
    ai = Enum.find(definition["extensions"], &(&1["id"] == "jido.ai"))
    config = ai["data"]
    [action, flow] = config["tools"]

    assert action["target"] == %{"id" => "tests/actions/jido-ai-multiply", "vsn" => 1}
    assert flow["target"] == %{"id" => "tests/flows/jido-ai-multiply", "vsn" => 1}
    assert config["controls"]["input"] == registered("input-control")
    assert config["controls"]["output"] == registered("output-control")
    refute Map.has_key?(config, "output")
    assert hd(definition["routes"])["handler"]["target"] == registered("handler")
  end

  @tag obligation: "jido_ai.agent.I5"
  test "an unknown model alias does not create an atom" do
    assert {:ok, document} =
             Jido.Authoring.encode(
               Assistant.definition(),
               registry: registry(),
               codec: Jido.Agent.Codec
             )

    unknown = "untrusted_contract_alias_#{System.unique_integer([:positive])}"
    extensions = document["definition"]["extensions"]
    ai_index = Enum.find_index(extensions, &(&1["id"] == "jido.ai"))
    ai = Enum.at(extensions, ai_index)

    invalid = put_in(ai["data"]["model"]["value"], unknown)
    invalid = put_in(document, ["definition", "extensions", Access.at(ai_index)], invalid)

    assert {:error, _issues} =
             Jido.Authoring.decode(invalid, registry: registry(), codec: Jido.Agent.Codec)

    assert_raise ArgumentError, fn -> String.to_existing_atom(unknown) end
  end

  @tag obligation: "jido_ai.agent.I6"
  test "the Signal Action owns structured reply shape" do
    config = Jido.AI.Plugin.config(Assistant)
    refute Map.has_key?(config, :output)

    assert %{schema: schema, type: "tests.jido_ai.answered"} = Ask.__signal_action__().output
    assert %Zoi.Types.Map{} = schema

    assert [route] = Assistant.definition().routes
    assert route.path == "tests.jido_ai.ask"
    assert route.handler == %{kind: :action, target: ObservePrepared}
  end

  @tag obligation: "jido_ai.agent.I7"
  test "the initializer completes candidate state and preserves caller state" do
    restored_session = Jido.Session.new!(id: "contract-session-restored")

    assert {:ok, first} =
             StatefulAssistant.instantiate(
               id: "contract-stateful-first",
               state: %{tone: "caller"}
             )

    assert {:ok, second} =
             StatefulAssistant.instantiate(id: "contract-stateful-second")

    assert {:ok, restored} =
             StatefulAssistant.instantiate(
               id: "contract-stateful-restored",
               state: %{session: restored_session}
             )

    assert first.state.tone == "caller"
    assert second.state.tone == "initialized"
    refute first.state.session.id == second.state.session.id
    assert restored.state == %{session: restored_session, tone: "initialized"}
    assert StatefulAssistant.definition().initial_state == %{}
    assert StatefulAssistant.definition().state == nil
  end

  defp registry do
    definition = Assistant.definition()

    Registry.new!(%{
      {"tests/agents/jido-ai-contract", 1} => {:agent, Assistant},
      {"tests/schemas/jido-ai-contract", 1} => {:schema, definition.schema},
      {"tests/extensions/jido-ai-audit", 1} => {:extension, AuditExtension},
      {"jido.ai", 1} => {:plugin, Jido.AI.Plugin},
      {"tests/actions/jido-ai-multiply", 1} => {:action, Multiply},
      {"tests/flows/jido-ai-multiply", 1} => {:flow, MultiplyFlow},
      {"tests/actions/jido-ai-input-control", 1} => {:action, PermitInput},
      {"tests/actions/jido-ai-output-control", 1} => {:action, CheckOutput},
      {"tests/actions/jido-ai-handler", 1} => {:action, ObservePrepared},
      {"tests/atoms/jido-ai-ask", 1} => {:atom, :ask}
    })
  end

  defp registered("input-control"),
    do: %{"id" => "tests/actions/jido-ai-input-control", "vsn" => 1}

  defp registered("output-control"),
    do: %{"id" => "tests/actions/jido-ai-output-control", "vsn" => 1}

  defp registered("handler"), do: %{"id" => "tests/actions/jido-ai-handler", "vsn" => 1}
end
