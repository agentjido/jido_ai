defmodule JidoAI.Examples.WorkerLifecycle.Hold do
  use Jido.Action, name: "hold", description: "Hold a real tool for worker lifetime checks"

  def run(_, context) do
    send(context.observer, {:worker_tool, self(), context[:tenant_id], context.agent_id})

    receive do
      :release -> {:ok, %{released: true}}
    end
  end
end

defmodule JidoAI.Examples.WorkerLifecycle.ReAct do
  use Jido.AI.Agent,
    name: "worker_lifecycle_react",
    model: %{
      id: "gpt-4o-mini",
      provider: :openai,
      provider_model_id: "gpt-4o-mini",
      extra: %{wire: %{protocol: "openai_chat"}}
    },
    tools: [JidoAI.Examples.WorkerLifecycle.Hold],
    tool_timeout_ms: 8_000,
    request_timeout_ms: 10_000,
    streaming: true
end

defmodule JidoAI.Examples.WorkerLifecycle.CoT do
  use Jido.AI.CoTAgent,
    name: "worker_lifecycle_cot",
    model: %{
      id: "gpt-4o-mini",
      provider: :openai,
      provider_model_id: "gpt-4o-mini",
      extra: %{wire: %{protocol: "openai_chat"}}
    },
    tools: [],
    tool_timeout_ms: 8_000,
    request_timeout_ms: 10_000,
    streaming: true
end
