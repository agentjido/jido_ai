defmodule JidoAI.Examples.ModelOptions.HttpAdapter do
  @moduledoc "Runs a request-scoped callback and sends the real HTTP request through Finch."
  def run(request) do
    callback = request.options.finch_private[:example_callback]
    request |> callback.() |> Req.Finch.run()
  end
end

defmodule JidoAI.Examples.ModelOptions.SwitchProbe do
  @moduledoc "A real tool separates model requests during a provider change."
  use Jido.Action, name: "switch_probe", schema: Zoi.object(%{n: Zoi.integer()})

  def run(%{n: n}, context) do
    send(context.observer, {:provider_tool, n})
    {:ok, %{n: n}}
  end
end

defmodule JidoAI.Examples.ModelOptions.Switch do
  @moduledoc "Selects Anthropic for the second call, then restores the configured default."
  def transform_request(request, state, _config, context) do
    send(context.observer, {:provider_transform, state.iteration, request.model})

    if state.iteration == 2 do
      {:ok, %{model: "anthropic:claude-sonnet-4-5", llm_opts: context.anthropic_options}}
    else
      {:ok, %{}}
    end
  end
end

for {module, streaming?} <- [
      {JidoAI.Examples.ModelOptions.StreamSwitchAgent, true},
      {JidoAI.Examples.ModelOptions.BufferedSwitchAgent, false}
    ] do
  defmodule module do
    @moduledoc "A native Agent uses one reasoning Flow across different provider formats."
    @streaming streaming?
    use Jido.Agent, name: "provider_switch", extensions: [Jido.AI.DSL]

    agent do
      schema(Zoi.object(%{reply: Zoi.string() |> Zoi.default("")}))

      ai :assistant do
        models do
          model(:answer, JidoAI.Examples.MockLLM.model())
        end

        reasoning :react do
          model(:answer)
          request_transformer(JidoAI.Examples.ModelOptions.Switch)
        end

        tools do
          action(JidoAI.Examples.ModelOptions.SwitchProbe, as: :switch_probe, forward_context: [:observer])
        end

        requests do
          mode(:session)
          streaming(@streaming)
        end

        result(nil, into: :reply)
      end
    end

    routes do
      route("ai.ask", ai(:assistant))
    end
  end
end
