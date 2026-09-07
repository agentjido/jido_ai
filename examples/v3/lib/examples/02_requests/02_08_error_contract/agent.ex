defmodule JidoAI.Examples.ErrorContract.Repair do
  @moduledoc "Returns a supplied error through the real repair callback boundary."
  def repair(_output, _raw, _reason, context) do
    send(context.observer, {:repair_called, self()})

    case context[:failure_mode] do
      :raise -> raise ArgumentError, "Fixture repair exception"
      :exit -> exit(:fixture_exit)
      :kill -> Process.exit(self(), :kill)
      _ -> {:error, context.failure}
    end
  end
end

defmodule JidoAI.Examples.ErrorContract.Control do
  @moduledoc "An application control can report a structured output rejection."
  @behaviour Jido.AI.Control
  def check(value, context) do
    case context[:failure_mode] do
      :action ->
        {:error,
         Jido.Action.Error.validation_error("Fixture invalid answer", %{
           field: :answer,
           value: value.answer,
           reason: :policy_rejected
         })}

      :core ->
        {:error,
         Jido.Error.execution_error("Fixture policy failure",
           details: %{value: value.answer, reason: :policy_rejected}
         )}

      _ ->
        case context[:failure] do
          nil -> :ok
          reason -> {:error, reason}
        end
    end
  end
end

defmodule JidoAI.Examples.ErrorContract.NativeAgent do
  @moduledoc "The native Agent DSL uses the same error boundary and request owner."
  use Jido.Agent, name: "native_error_contract", extensions: [Jido.AI.DSL]

  agent do
    schema Zoi.object(%{reply: Zoi.map() |> Zoi.default(%{})})

    ai :assistant do
      models do
        model(:answer, :example)
      end

      reasoning :react do
        model(:answer)
      end

      controls do
        output(JidoAI.Examples.ErrorContract.Control)
      end

      requests do
        mode(:session)
      end

      result(Zoi.object(%{answer: Zoi.string()}), into: :reply)
    end
  end

  routes do
    route "ai.ask", ai(:assistant)
  end
end

defmodule JidoAI.Examples.ErrorContract.Agent do
  @moduledoc "A typed Agent whose repair callback can report structured failures."
  use Jido.AI.Agent,
    name: "error_contract_agent",
    tools: [],
    model: :example,
    streaming: false,
    output: [
      schema: Zoi.object(%{answer: Zoi.string()}),
      retries: 1,
      repair_fun: {JidoAI.Examples.ErrorContract.Repair, :repair}
    ]
end

defmodule JidoAI.Examples.ErrorContract.Transform do
  @moduledoc "Rejects a model request through the public transformer contract."
  @behaviour Jido.AI.Reasoning.ReAct.RequestTransformer
  def transform_request(_request, _state, _config, context), do: {:error, context.failure}
end

defmodule JidoAI.Examples.ErrorContract.TransformAgent do
  @moduledoc "Exposes transformer failures before any provider request."
  use Jido.AI.Agent,
    name: "error_transform_agent",
    tools: [],
    model: :example,
    streaming: false,
    request_transformer: JidoAI.Examples.ErrorContract.Transform
end
