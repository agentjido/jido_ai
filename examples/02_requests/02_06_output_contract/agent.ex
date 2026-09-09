defmodule JidoAI.Examples.OutputContract.Schema do
  @moduledoc "Typed ticket items use declared enums and default values."
  def output do
    Zoi.object(%{
      items:
        Zoi.array(
          Zoi.object(%{
            category: Zoi.enum([:billing, :technical]),
            confidence: Zoi.float() |> Zoi.default(1.0),
            summary: Zoi.string() |> Zoi.min(1)
          })
        )
    })
  end
end

defmodule JidoAI.Examples.OutputContract.Telemetry do
  @moduledoc "Forwards only the test's correlated telemetry to its observer."
  def handle(event, measurements, metadata, %{observer: observer, request_id: id}) do
    if metadata.request_id == id, do: send(observer, {:observed, event, measurements, metadata})
  end
end

defmodule JidoAI.Examples.OutputContract.Agent do
  @moduledoc "A typed ticket Agent with bounded output repair."
  use Jido.AI.Agent,
    name: "output_contract_agent",
    tools: [],
    model: :example,
    streaming: false,
    output: [schema: JidoAI.Examples.OutputContract.Schema.output(), retries: 2]
end

defmodule JidoAI.Examples.OutputContract.StreamAgent do
  @moduledoc "The same output contract after streamed model and tool responses."
  use Jido.AI.Agent,
    name: "stream_output_contract_agent",
    tools: [JidoAI.Examples.RequestScope.Echo],
    model: :example,
    streaming: true,
    output: [schema: JidoAI.Examples.OutputContract.Schema.output(), retries: 2]
end

defmodule JidoAI.Examples.OutputContract.Callback do
  @moduledoc "Holds a repair so the test can cancel it through the public request API."
  def wait(_output, _raw, _reason, context) do
    send(context.observer, {:repair_waiting, self()})

    receive do
      :release -> {:ok, %{items: [%{category: :billing, summary: "Released"}]}}
    end
  end
end

defmodule JidoAI.Examples.OutputContract.Reject do
  @moduledoc "Rejects a valid object at the application output control."
  @behaviour Jido.AI.Control
  def check(_, _), do: {:error, :output_not_allowed}
end

defmodule JidoAI.Examples.OutputContract.NativeAgent do
  @moduledoc "Native authoring keeps event delivery separate from telemetry flags."
  use Jido.Agent, name: "native_output_contract", extensions: [Jido.AI.DSL]

  agent do
    schema Zoi.object(%{reply: Zoi.map() |> Zoi.default(%{})})

    ai :assistant do
      observability do
        emit_llm_deltas(false)
      end

      models do
        model(:answer, :example)
      end

      reasoning :react do
        model(:answer)
      end

      requests do
        mode(:session)
        streaming(true)
      end

      result(JidoAI.Examples.OutputContract.Schema.output(), into: :reply)
    end
  end

  routes do
    route "ai.ask", ai(:assistant)
  end

  def source do
    %{
      id: :assistant,
      observability: %{emit_llm_deltas?: false},
      models: %{answer: :example},
      reasoning: %{method: :react, model: :answer},
      requests: %{mode: :session, streaming: true},
      result: %{schema: JidoAI.Examples.OutputContract.Schema.output(), into: :reply},
      routes: ["ai.ask"]
    }
  end

  def base do
    Jido.Agent.new!(
      name: "native_output_contract",
      module: __MODULE__,
      vsn: vsn(),
      schema: Zoi.object(%{reply: Zoi.map() |> Zoi.default(%{})})
    )
  end
end
