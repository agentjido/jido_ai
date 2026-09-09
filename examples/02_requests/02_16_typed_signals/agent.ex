defmodule JidoAI.Examples.TypedSignals.Echo do
  use Jido.Action, name: "echo", schema: Zoi.object(%{value: Zoi.string()})

  def run(params, context) do
    send(context.observer, {:echo_executed, params.value})
    {:ok, %{echo: params.value}}
  end
end

defmodule JidoAI.Examples.TypedSignals.Hold do
  use Jido.Action, name: "hold"

  def run(_, context) do
    send(context.observer, {:held_action, self()})

    receive do
      :release -> {:ok, %{released: true}}
    end
  end
end

defmodule JidoAI.Examples.TypedSignals.Chat do
  use Jido.Agent, name: "typed_signal_chat", extensions: [Jido.AI.DSL]

  agent do
    schema Zoi.object(%{reply: Zoi.string() |> Zoi.default("")})

    ai :assistant do
      models do
        model(:answer, JidoAI.Examples.MockLLM.model())
      end

      reasoning :react do
        model(:answer)
      end

      tools do
        action JidoAI.Examples.TypedSignals.Echo, as: :echo, forward_context: [:observer]
      end

      requests do
        mode(:session)
        streaming(true)
      end

      result(nil, into: :reply)
    end
  end

  routes do
    route "ai.ask", ai(:assistant)
  end
end

defmodule JidoAI.Examples.TypedSignals.Publish do
  use Jido.Action, name: "publish_ai_event"

  def run(%{event: event}, context) do
    with {:ok, directives} <- Jido.AI.Signal.emit(event),
         do:
           {:ok,
            %{
              context.agent_state
              | published: context.agent_state.published + length(directives)
            }, directives}
  end

  def run(%{typed: typed}, context),
    do:
      {:ok, %{context.agent_state | published: context.agent_state.published + 1},
       [%Jido.Agent.Directive.Emit{signal: typed}]}
end

defmodule JidoAI.Examples.TypedSignals.Outbound do
  use Jido.Plugin

  def prepare_dispatch(_, signal, context, _) do
    if context.turn_context[:reject_delivery],
      do: {:error, :delivery_rejected},
      else: {:ok, %{signal | subject: "version-#{context.state_version}"}}
  end
end

defmodule JidoAI.Examples.TypedSignals.Publisher do
  use Jido.Agent, name: "typed_signal_publisher"

  agent do
    schema Zoi.object(%{published: Zoi.integer() |> Zoi.default(0)})
    plugin JidoAI.Examples.TypedSignals.Outbound
  end

  routes do
    route "ai.event", JidoAI.Examples.TypedSignals.Publish
  end
end
