defmodule JidoAI.Examples.PublicAgent.Probe do
  @moduledoc "A real tool that checks request context and can fail once."
  use Jido.Action, name: "public_probe", schema: Zoi.object(%{value: Zoi.integer()})

  def run(params, context) do
    attempt = Agent.get_and_update(context.counter, &{&1 + 1, &1 + 1})
    send(context.observer, {:public_probe, attempt, context.tenant, context.state.last_query})

    if (attempt == 1 && Map.get(context, :fail_once, false)) ||
         Map.get(context, :fail_always, false),
       do:
         {:error,
          Jido.Action.Error.execution_error("Try again", %{
            retry: Map.get(context, :retryable, true)
          })},
       else: {:ok, %{value: params.value, tenant: context.tenant}}
  end
end

defmodule JidoAI.Examples.PublicAgent.Agent do
  @moduledoc "The public option macro uses the same v3 session and reasoning Flow."
  @prompt "Use the case facts and the available tools."
  use Jido.AI.Agent,
    name: "public_agent",
    tools: [JidoAI.Examples.PublicAgent.Probe],
    model: :example,
    system_prompt: @prompt,
    streaming: false,
    tool_retry_backoff_ms: 1,
    tool_context: %{tenant: "base"},
    llm_opts: [temperature: 0.1]
end

defmodule JidoAI.Examples.PublicAgent.StreamAgent do
  @moduledoc "The default public Agent uses provider streaming."
  use Jido.AI.Agent, name: "public_stream_agent", tools: [], model: :example
end

defmodule JidoAI.Examples.PublicAgent.ObjectAgent do
  @moduledoc "Typed results retain the public text view in last_answer."
  use Jido.AI.Agent,
    name: "public_object_agent",
    tools: [],
    model: :example,
    streaming: false,
    output: [schema: Zoi.object(%{answer: Zoi.string()}), retries: 0]
end
