defmodule JidoAI.Examples.ToolEffects.Record do
  @moduledoc "Records a post-commit observation through a real core Plugin."
  defstruct [:receiver, :label]
end

defmodule JidoAI.Examples.ToolEffects.Observer do
  @moduledoc false
  use Jido.Plugin
  alias JidoAI.Examples.ToolEffects.Record
  def directives(_), do: [Record]

  def validate_directive(%Record{receiver: receiver, label: label} = value, _)
      when is_pid(receiver) and is_binary(label), do: {:ok, value}

  def validate_directive(_, _), do: {:error, :invalid_record_directive}

  def dispatch(nil, directive, context, _) do
    server = Jido.whereis_agent(context.jido, context.agent_id, partition: context.partition)

    send(
      directive.receiver,
      {:effect_committed, directive.label, Jido.AgentServer.agent(server).state}
    )

    :ok
  end
end

defmodule JidoAI.Examples.ToolEffects.Tool do
  @moduledoc "Proposes a complete state and typed post-commit work."
  use Jido.Action,
    name: "change_case",
    schema:
      Zoi.object(%{
        kind: Zoi.string(),
        field: Zoi.enum([:count, :label]) |> Zoi.default(:count),
        value: Zoi.integer() |> Zoi.default(1)
      })

  alias JidoAI.Examples.ToolEffects.Record

  def run(params, context) do
    send(context.observer, {:effect_tool, self(), params, context.agent_state})

    if params.kind == "hold",
      do:
        (receive do
           :release -> :ok
         end)

    value = if params.field == :label, do: Integer.to_string(params.value), else: params.value
    next = Map.put(context.agent_state, params.field, value)
    record = %Record{receiver: context.observer, label: Atom.to_string(params.field)}
    effects = [Jido.AI.Effects.state(next), record]

    signal =
      Jido.Signal.new!("effects.tick", %{value: params.value}, %{source: "/examples/effects"})

    case params.kind do
      "file" ->
        File.write!(context.effect_file, "Tool side effect")
        {:ok, %{written: true}, effects}

      "content" ->
        {:ok,
         Jido.Action.Output.raw(%ReqLLM.ToolResult{
           output: %{value: value},
           content: [ReqLLM.Message.ContentPart.text("Tool content")]
         }), effects}

      "read" ->
        {:ok, %{count: context.agent_state.count, label: context.agent_state.label}}

      "protected" ->
        {:ok, %{}, [Jido.AI.Effects.state(Map.put(next, :requests, %{"forged" => %{}})), record]}

      "invalid_state" ->
        {:ok, %{}, [Jido.AI.Effects.state(%{next | count: "bad"}), record]}

      "invalid_directive" ->
        {:ok, %{}, [Jido.AI.Effects.state(next), %{record | label: nil}]}

      "error" ->
        {:error, Jido.Action.Error.execution_error("Effectful failure", %{retry: true}), effects}

      "emit" ->
        {:ok, %{value: value},
         [
           Jido.AI.Effects.state(next),
           Jido.Plugin.Dispatch.send(signal, {:pid, target: context.observer})
         ]}

      "schedule" ->
        {:ok, %{value: value}, [Jido.AI.Effects.state(next), Jido.Plugin.Scheduler.schedule(params.value, signal)]}

      _ ->
        {:ok, %{value: value}, effects}
    end
  end
end

defmodule JidoAI.Examples.ToolEffects.Change do
  @moduledoc "An ordinary route can commit while the model is working."
  use Jido.Action,
    name: "effects_external_change",
    schema: Zoi.object(%{field: Zoi.enum([:count, :label]), value: Zoi.any()})

  def run(params, context), do: {:ok, Map.put(context.agent_state, params.field, params.value)}
end

defmodule JidoAI.Examples.ToolEffects.Tick do
  @moduledoc false
  use Jido.Action, name: "effects_tick"
  def run(_, context), do: {:ok, %{context.agent_state | ticks: context.agent_state.ticks + 1}}
end

defmodule JidoAI.Examples.ToolEffects.Reject do
  @moduledoc false
  @behaviour Jido.AI.Control
  def check(_, _), do: {:error, :fixture_output_rejected}
end

defmodule JidoAI.Examples.ToolEffects.PublicTool do
  @moduledoc false
  use Jido.Action, name: "public_effect"

  def run(_, context) do
    {:ok, %{changed: true},
     [
       Jido.AI.Effects.state(%{context.agent_state | model: :changed}),
       %JidoAI.Examples.ToolEffects.Record{receiver: context.observer, label: "public"}
     ]}
  end
end

defmodule JidoAI.Examples.ToolEffects.PublicAgent do
  @moduledoc "Existing Agent effect options use the shared policy and candidate code."
  use Jido.AI.Agent,
    name: "public_effect_agent",
    model: :example,
    tools: [JidoAI.Examples.ToolEffects.PublicTool],
    streaming: false,
    plugins: [JidoAI.Examples.ToolEffects.Observer],
    effect_policy: %{allow: [Jido.AI.Effects.State]},
    strategy_effect_policy: %{mode: :allow_all}
end

defmodule JidoAI.Examples.ToolEffects.Agent do
  @moduledoc "Tools stage state and directives; the Agent commits the complete result."
  use Jido.Agent, name: "tool_effects", extensions: [Jido.AI.DSL]

  agent do
    schema Zoi.object(%{
             reply: Zoi.string() |> Zoi.default(""),
             count: Zoi.integer() |> Zoi.default(0),
             label: Zoi.string() |> Zoi.default("open"),
             ticks: Zoi.integer() |> Zoi.default(0)
           })

    plugin JidoAI.Examples.ToolEffects.Observer
    plugin Jido.Plugin.Dispatch
    plugin Jido.Plugin.Scheduler

    ai :assistant do
      effect_policy(%{
        allow: [
          Jido.AI.Effects.State,
          JidoAI.Examples.ToolEffects.Record,
          Jido.Plugin.Dispatch.Send,
          Jido.Plugin.Scheduler.Schedule
        ]
      })

      models do
        model(:answer, JidoAI.Examples.MockLLM.model())
      end

      reasoning :react do
        model(:answer)
        effect_policy(%{mode: :allow_all})
        tool_concurrency(2)
      end

      tools do
        action JidoAI.Examples.ToolEffects.Tool,
          as: :change_case,
          forward_context: [:observer, :agent_state, :effect_file],
          timeout: 5_000
      end

      requests do
        mode(:session)
      end

      result(nil, into: :reply)
    end
  end

  routes do
    route "ai.ask", ai(:assistant)
    route "effects.change", JidoAI.Examples.ToolEffects.Change
    route "effects.tick", JidoAI.Examples.ToolEffects.Tick
  end
end
