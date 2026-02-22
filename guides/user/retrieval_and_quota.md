# Retrieval And Quota

You need memory-aware responses and budget controls before production traffic scales.

After this guide, you can enable retrieval and quota plugins, run retrieval/quota actions directly, and understand request-rewrite behavior.

> **⚠️ ReAct agents and retrieval enrichment**
>
> You enabled retrieval but your ReAct agent ignores memory? That's expected.
> `Jido.AI.Agent.ask/ask_sync` emits `ai.react.query`, and retrieval auto-enrichment
> only runs on `chat.message` and `reasoning.*.run` signals.
>
> For ReAct query enrichment, recall memory first and prepend it to the prompt explicitly.
> See [First Agent](first_react_agent.md) for the ReAct request flow.

## 1. Enable Retrieval And Quota In An Agent

```elixir
defmodule MyApp.Actions.Multiply do
  use Jido.Action,
    name: "multiply",
    schema: Zoi.object(%{a: Zoi.integer(), b: Zoi.integer()})

  @impl true
  def run(%{a: a, b: b}, _context), do: {:ok, %{product: a * b}}
end

defmodule MyApp.SupportAgent do
  use Jido.AI.Agent,
    name: "support_agent",
    model: :fast,
    tools: [MyApp.Actions.Multiply],
    retrieval: %{
      enabled: true,
      namespace: "support_memory",
      top_k: 3,
      max_snippet_chars: 280
    },
    quota: %{
      enabled: true,
      scope: "support_ops",
      window_ms: 60_000,
      max_requests: 100,
      max_total_tokens: 40_000,
      error_message: "quota exceeded for current window"
    }
end
```

The `retrieval:` and `quota:` options are opt-in plugin config shortcuts on `Jido.AI.Agent`.

## 2. Manage Memory With Retrieval Actions

```elixir
alias Jido.AI.Actions.Retrieval.{UpsertMemory, RecallMemory, ClearMemory}

context = %{plugin_state: %{retrieval: %{namespace: "support_memory"}}}

{:ok, %{retrieval: %{last_upsert: _entry}}} =
  Jido.Exec.run(UpsertMemory, %{text: "Customer prefers email updates", metadata: %{customer_id: "c-123"}}, context)

{:ok, %{retrieval: %{memories: memories}}} =
  Jido.Exec.run(RecallMemory, %{query: "How should we contact customer c-123?", top_k: 3}, context)

# Use ClearMemory when you need to drop namespace memory:
{:ok, %{retrieval: %{cleared: _count}}} = Jido.Exec.run(ClearMemory, %{}, context)
```

`namespace` resolution for retrieval actions:

1. explicit action param
2. `context[:plugin_state][:retrieval][:namespace]`
3. `context[:state][:retrieval][:namespace]`
4. `context[:agent][:id]`
5. `"default"`

## 3. Understand Retrieval Auto-Enrichment Scope

Retrieval plugin enrichment currently applies to:

- `chat.message`
- `reasoning.*.run`

Per-request opt-out:

```elixir
signal =
  Jido.Signal.new!(
    "chat.message",
    %{prompt: "Draft a response for customer c-123", disable_retrieval: true},
    source: "/docs"
  )
```

See the [ReAct + retrieval gotcha](#⚠️-react-agents-and-retrieval-enrichment) at the top of this guide for details on why `ai.react.query` is not enriched.

## 4. Track And Reset Quota

```elixir
alias Jido.AI.Actions.Quota.{GetStatus, Reset}

context = %{plugin_state: %{quota: %{scope: "support_ops", window_ms: 60_000, max_total_tokens: 40_000}}}

{:ok, %{quota: status}} = Jido.Exec.run(GetStatus, %{}, context)
# status includes: usage, limits, remaining, over_budget?

{:ok, %{quota: %{scope: "support_ops", reset: true}}} = Jido.Exec.run(Reset, %{}, context)
```

`scope` resolution for quota actions:

1. explicit action param
2. `context[:plugin_state][:quota][:scope]`
3. `context[:state][:quota][:scope]`
4. `context[:agent][:id]`
5. `"default"`

## 5. Quota Rewrite Behavior

When over budget, request/query signals in these families are rewritten to `ai.request.error`:

- `chat.*`
- `ai.*.query`
- `reasoning.*.run`

Rewrite payload fields:

- `request_id`
- `reason: :quota_exceeded`
- `message` from quota config

`ai.usage` drives counters; token accounting uses `total_tokens` first, then `input_tokens + output_tokens`.

## Failure Mode: Retrieval Returns No Memories

Symptom:
- `RecallMemory` returns `memories: []`
- no retrieval snippets appear in enriched prompts

Fix:
- verify namespace alignment (`upsert` and `recall` must target same namespace)
- increase `top_k`
- ensure query text overlaps stored memory text

## Failure Mode: Requests Rejected As Over Budget

Symptom:
- request resolves to quota-related `ai.request.error`

Fix:
- inspect quota status via `Jido.AI.Actions.Quota.GetStatus`
- increase `max_requests` / `max_total_tokens` or shorten response budgets
- reset counters with `Jido.AI.Actions.Quota.Reset` during testing

## Defaults You Should Know

- Retrieval defaults: `enabled: true`, `top_k: 3`, `max_snippet_chars: 280`
- Quota defaults: `enabled: true`, `window_ms: 60_000`, `max_requests: nil`, `max_total_tokens: nil`
- Quota error default message in plugin runtime: `"quota exceeded for current window"`

## When To Use / Not Use

Use this path when:
- responses should use short-term memory context
- you must enforce request/token budgets

Do not use this path when:
- workload is stateless and unconstrained (for example local prototyping only)

## Next

- [Tool Calling With Actions](tool_calling_with_actions.md)
- [Request Lifecycle And Concurrency](request_lifecycle_and_concurrency.md)
- [Actions Catalog](../developer/actions_catalog.md)
