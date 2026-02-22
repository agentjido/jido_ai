# First Agent

You want a production-shaped `Jido.AI.Agent` with tools, request handles, and explicit runtime control.

After this guide, you will run a custom tool, submit async requests, and await specific request IDs.

## Build The Tool

```elixir
defmodule MyApp.Actions.AddNumbers do
  use Jido.Action,
    name: "add_numbers",
    schema: Zoi.object(%{a: Zoi.integer(), b: Zoi.integer()})

  @impl true
  def run(%{a: a, b: b}, _context), do: {:ok, %{sum: a + b}}
end
```

## Build The Agent

```elixir
defmodule MyApp.MathAgent do
  use Jido.AI.Agent,
    name: "math_agent",
    model: :fast,
    tools: [MyApp.Actions.AddNumbers],
    max_iterations: 8,
    system_prompt: "Solve accurately. Use tools for arithmetic."
end
```

## Run Async + Await

```elixir
{:ok, pid} = Jido.AgentServer.start(agent: MyApp.MathAgent)

{:ok, req} = MyApp.MathAgent.ask(pid, "What is 19 + 23?")
{:ok, result} = MyApp.MathAgent.await(req, timeout: 15_000)
```

## Optional: Set Tool Context At Runtime

```elixir
signal = Jido.Signal.new!(
  "ai.react.set_tool_context",
  %{tool_context: %{tenant_id: "acme"}},
  source: "/docs/example"
)

:ok = Jido.AgentServer.cast(pid, signal)
```

## Optional: Set System Prompt At Runtime

```elixir
{:ok, _agent} = Jido.AI.set_system_prompt(pid, "You are a concise support specialist.")
```

## Note: Retrieval And ReAct

If you enable the retrieval plugin, auto-enrichment does **not** run on `ai.react.query` signals.
Recall memory explicitly and prepend it to your prompt. See [Retrieval And Quota](retrieval_and_quota.md) for details.

## Failure Mode: Tool Not Registered / Not Valid

Symptom:
- Request completes with tool error
- `{:error, :not_a_tool}` when registering dynamically

Fix:
- Ensure module exports `name/0`, `schema/0`, and `run/2`
- Validate module with `Jido.AI.register_tool(pid, ToolModule)`

## Defaults You Should Know

- `request_policy` default: `:reject`
- Tool timeout default: `15_000ms`
- Tool retry defaults: `1` retry, `200ms` backoff

## When To Use / Not Use

Use this approach when:
- You need reasoning plus tool execution
- You need per-request correlation and awaiting

Do not use this approach when:
- You only need deterministic, single-pass text completion

## Next

- [Request Lifecycle And Concurrency](request_lifecycle_and_concurrency.md)
- [Tool Calling With Actions](tool_calling_with_actions.md)
- [Directives Runtime Contract](../developer/directives_runtime_contract.md)
