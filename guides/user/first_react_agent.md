# First Agent

You want a production-shaped `Jido.AI.Agent` with tools, request handles, and explicit runtime control.

After this guide, you will run a custom tool, submit async requests, and await specific request IDs.

## Build The Tool

```elixir
defmodule MyApp.Actions.AddNumbers do
  use Jido.Action,
    name: "add_numbers",
    schema: Zoi.object(%{a: Zoi.integer(), b: Zoi.integer()}),
    description: "Add two numbers."

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
    system_prompt: "Solve accurately. Use tools for arithmetic.",
    llm_opts: [thinking: %{type: :enabled, budget_tokens: 2048}, reasoning_effort: :high]
end
```

## Optional: Configure Tool Effect Policy

Use `effect_policy` to bound which tool-emitted effects are allowed at runtime.

```elixir
defmodule MyApp.SafeMathAgent do
  use Jido.AI.Agent,
    name: "safe_math_agent",
    model: :fast,
    tools: [MyApp.Actions.AddNumbers],
    effect_policy: %{
      mode: :allow_list,
      allow: [Jido.Agent.StateOp.SetState, Jido.Agent.Directive.Emit]
    },
    strategy_effect_policy: %{
      constraints: %{
        emit: %{allowed_signal_prefixes: ["app.math."]}
      }
    }
end
```

`strategy_effect_policy.constraints` accepts atom keys, string keys, or keyword lists (including nested `emit` and `schedule` maps). Inputs are normalized before policy enforcement.

## Run Async + Await

```elixir
{:ok, pid} = Jido.AgentServer.start(agent: MyApp.MathAgent)

{:ok, req} = MyApp.MathAgent.ask(pid, "What is 19 + 23?")
{:ok, result} = MyApp.MathAgent.await(req, timeout: 15_000)

# Per-request overrides
{:ok, req2} =
  MyApp.MathAgent.ask(pid, "Explain how you solved that",
    llm_opts: [reasoning_effort: :medium]
  )
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

## Optional: Restore A Conversation Thread

If you persist the conversation history (e.g. from `snapshot.details.conversation`),
you can restore it on restart so the agent resumes where it left off.

```elixir
saved_messages = snapshot.details.conversation

# Split out one leading system message (if present) so it does not become
# a duplicate thread entry.
{saved_system_prompt, conversation_messages} =
  case saved_messages do
    [%{role: role, content: content} | rest]
    when role in [:system, "system"] and is_binary(content) ->
      {content, rest}

    _ ->
      {nil, saved_messages}
  end

# At start time — pass the saved thread via initial_state:
thread =
  Jido.AI.Thread.new(system_prompt: saved_system_prompt)
  |> Jido.AI.Thread.append_messages(conversation_messages)

Jido.AgentServer.start_link(agent: MyAgent, initial_state: %{thread: thread})

# Or at runtime on an already-running agent:
{:ok, _agent} = Jido.AI.set_thread(pid, thread)
```

If `set_thread` is called while a request is active, replacement is deferred
and applied after that request reaches a terminal state.

If the thread carries a non-nil `system_prompt`, the agent's config prompt is
synchronized automatically. If `thread.system_prompt` is `nil`, the `nil` is
preserved and config prompt stays unchanged.

Init-time note: when restoring with `initial_state: %{thread: thread}`, a nil
`thread.system_prompt` is backfilled from the agent's configured prompt.

Runtime note: when restoring with `Jido.AI.set_thread/3`, a nil
`thread.system_prompt` stays nil.

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
