defmodule JidoAI.Examples.SignalDelivery.Probe do
  @moduledoc "A real outbound Plugin with controlled dispatch and admission failures."
  use Jido.Plugin

  def admit(_, command, _) do
    config = Application.get_env(:jido_ai, :delivery_probe, %{})

    if command.signal.type == Jido.AI.Session.publish_type() do
      if observer = config[:observer],
        do: send(observer, {:publish_admitted, command.signal, command.context})

      if config[:hold_admission] do
        send(config.observer, {:admission_held, self()})

        receive do
          :release -> :ok
        end
      end

      if config[:reject_admission],
        do: {:error, :delivery_admission_rejected},
        else: {:ok, command}
    else
      {:ok, command}
    end
  end

  def prepare_dispatch(_, signal, context, _) do
    config = Application.get_env(:jido_ai, :delivery_probe, %{})

    if observer = config[:observer],
      do: send(observer, {:outbound, signal, context, self()})

    cond do
      config[:reject] == signal.type ->
        {:error, :delivery_rejected}

      config[:hold] == signal.type ->
        receive do
          :release -> {:ok, %{signal | subject: "version-#{context.state_version}"}}
        end

      true ->
        {:ok, %{signal | subject: "version-#{context.state_version}"}}
    end
  end
end

defmodule JidoAI.Examples.SignalDelivery.Count do
  use Jido.Action, name: "count_observation"

  def run(_, context),
    do: {:ok, %{context.agent_state | observed: context.agent_state.observed + 1}}
end

defmodule JidoAI.Examples.SignalDelivery.Agent do
  @moduledoc "The owning Agent emits typed Signals through core dispatch after each session event."
  use Jido.Agent, name: "signal_delivery", extensions: [Jido.AI.DSL]

  agent do
    schema Zoi.object(%{
             reply: Zoi.string() |> Zoi.default(""),
             observed: Zoi.integer() |> Zoi.default(0)
           })

    plugin JidoAI.Examples.SignalDelivery.Probe

    ai :assistant do
      observability(%{emit_signals?: true})

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

defmodule JidoAI.Examples.SignalDelivery.PublicAgent do
  use Jido.AI.Agent, name: "public_signal_delivery", model: :example, tools: [], streaming: true
end

defmodule JidoAI.Examples.SignalDelivery.Adapter do
  @moduledoc "A real dispatch adapter can reject a Signal after outbound preparation."
  @behaviour Jido.Signal.Dispatch.Adapter
  def options_schema,
    do: Zoi.keyword([target: Zoi.any() |> Zoi.required()], unrecognized_keys: :error)

  def deliver(signal, opts) do
    send(opts[:target], {:adapter_called, signal})

    if signal.type == "ai.request.completed",
      do: {:error, :adapter_refused},
      else:
        (
          send(opts[:target], {:signal, signal})
          :ok
        )
  end
end
