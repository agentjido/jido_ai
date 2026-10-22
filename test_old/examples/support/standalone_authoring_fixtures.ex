defmodule JidoAI.Examples.StandaloneAuthoring.Transform do
  def transform_request(request, _state, _config, context) do
    send(context.observer, {:standalone_count, context.state.count})
    {:ok, %{tools: request.tools}}
  end
end

defmodule JidoAI.Examples.StandaloneAuthoring.Repair do
  def fix(_output, _raw, _reason, context) do
    send(context.observer, :standalone_repair)
    {:ok, %{answer: "Repaired"}}
  end
end
