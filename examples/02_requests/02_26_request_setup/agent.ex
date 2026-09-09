for {module, streaming?, mode} <- [
      {JidoAI.Examples.RequestSetup.NativeStream, true, :session},
      {JidoAI.Examples.RequestSetup.NativeBuffered, false, :session},
      {JidoAI.Examples.RequestSetup.TurnStream, true, :turn},
      {JidoAI.Examples.RequestSetup.TurnBuffered, false, :turn}
    ] do
  defmodule module do
    @moduledoc "A native profile with declared HTTP and generation options."
    @streaming streaming?
    @mode mode
    use Jido.Agent, name: "request_setup_native", extensions: [Jido.AI.DSL]

    agent do
      schema(Zoi.object(%{reply: Zoi.string() |> Zoi.default("")}))

      ai :assistant do
        models do
          model :answer, JidoAI.Examples.MockLLM.model() do
            generation(
              temperature: 0.3,
              max_tokens: 73,
              req_http_options: [headers: [{"x-declared", "present"}], retry: false]
            )
          end
        end

        reasoning :react do
          model(:answer)
        end

        requests do
          mode(@mode)
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

defmodule JidoAI.Examples.RequestSetup.OptionsStream do
  @moduledoc "The public Agent macro accepts string-key model option maps."
  use Jido.AI.Agent,
    name: "request_setup_optionsstream",
    tools: [],
    model: :request_setup_example,
    streaming: true,
    llm_opts: %{"temperature" => 0.3, "max_tokens" => 73},
    req_http_options: [headers: [{"x-declared", "present"}], retry: false]
end

defmodule JidoAI.Examples.RequestSetup.OptionsBuffered do
  @moduledoc "The public Agent macro accepts string-key model option maps."
  use Jido.AI.Agent,
    name: "request_setup_optionsbuffered",
    tools: [],
    model: :request_setup_example,
    streaming: false,
    llm_opts: %{"temperature" => 0.3, "max_tokens" => 73},
    req_http_options: [headers: [{"x-declared", "present"}], retry: false]
end
