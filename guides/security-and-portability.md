# Security and Portability

A support Agent that can issue refunds needs three guarantees: the model can
call only the tools you allowed, the records it keeps don't leak secrets, and
a repeated call doesn't refund twice. This guide covers tool trust, request
narrowing, redaction, portable state, and idempotent effects. Read
[Action Tools](action-tools.livemd) and
[Dynamic Tool Sources](dynamic-tool-sources.md) first. The examples use
`MyApp.LookupOrder` and the `MyApp.OfflineModel` helper from
[Getting Started](getting-started.livemd).

```elixir
# Request data narrows the Agent's tools for this call.
signal =
  MyApp.SupportAgent.request_signal!(%{
    input: "Where is order A-1001?",
    tool_policy: %{hidden: ["issue_refund"]}
  })

# Host code adds trusted tools from a source for this call.
MyApp.SupportAgent.cmd(agent, signal,
  context: %{jido_ai_tool_sources: [{MyApp.HelpCenterTools, %{tenant: "acme"}}]}
)
```

The Agent definition's `tools` block sets the allowlist at compile time.
Nothing in the request can add a tool the model can run.

## Trust Boundaries

| Source | Set by | Can add tools |
| --- | --- | --- |
| `tools` in the Agent definition | Your code, at compile time | Yes. The static allowlist. |
| `jido_ai_tool_sources` in the execution context | Host code that calls `cmd/3` or the Agent Server | Yes. Trusted dynamic tools. |
| `tool_policy` in the request | Signal data | No. It can only hide tools or require review. |
| `options` in the request | Signal data | No. |

Signal data comes from whoever sends the Signal. Treat it like any request
body. The execution context comes from the process that calls the Agent, so
only your code can add a `Jido.AI.ToolSource`.

## Narrow Each Request

`tool_policy` selects a subset of the combined tools:

| Field | Effect |
| --- | --- |
| `visible` | Only these names. `[]` means all. |
| `hidden` | Remove these names. |
| `review` | These names need approval before they run. |
| `requirement` | `:optional`, `:required`, `:per_turn`, or `:disabled`. |

Every name must already be in the allowlist:

```elixir
Jido.AI.Toolset.select([MyApp.LookupOrder, MyApp.IssueRefund], %{
  hidden: ["issue_refund"]
})
|> then(fn {:ok, selection} -> {selection.visible, selection.hidden} end)
# => {["lookup_order"], ["issue_refund"]}

Jido.AI.Toolset.select([MyApp.LookupOrder, MyApp.IssueRefund], %{visible: ["delete_account"]})
# => {:error, {:unknown_tool, "delete_account"}}
```

In a request, the unknown name fails before any model call with
`{:error, %Jido.Action.Error.ExecutionFailureError{}}`. Hidden tools aren't
sent to the provider.

## What the Model Can Run

The model sees a tool definition for each visible tool, built from the
Action's name, description, and Zoi schema with `strict: true`. When it
answers with tool calls, the output guard checks every call before any of
them runs:

- a name outside the request tool set is rejected with
  `model requested a tool that is not allowed`;
- arguments that fail the Action schema are rejected with
  `invalid tool call: {:invalid_tool_arguments, name}`.

A rejected response doesn't run a tool. ReAct asks the model to repair it, and
the request ends with `reason_code: :output` when repairs run out.
[Tool Execution and Results](tool-execution-and-results.md) covers the full
validation list.

## Server-Side Options

`options` go to ReqLLM as call options. They include `api_key`, `base_url`,
and `req_http_options`. Jido AI removes `tool_choice` and, when the request
has visible tools, sets `tools` from them. It passes the other keys through.

> #### Don't forward client options {: .warning}
>
> Build `options` from your own configuration. Copying them from a client
> request lets that client choose the provider endpoint and credentials for
> the call.

A request override replaces the whole `options` map, including the Agent's
defaults.

## Model-Visible Results

A tool's local value stays in the tool attempt record. The model sees a JSON
copy bounded by `limits.tool_output_bytes` (default 16,384 bytes). A larger
result reaches the model as:

```elixir
%{
  "status" => "truncated",
  "message" => "tool result exceeded the model-content limit",
  "original_bytes" => 20_480,
  "max_bytes" => 16_384
}
```

A tool error reaches the model as its `type`, `message`, and `retryable`
flag. A raised exception's message reaches the model as written. Don't put
secrets, tokens, or internal URLs in tool error messages.

## Redaction

Each model attempt stores two `Jido.AI.Context.Snapshot` documents, before
and after the call. Snapshots replace PIDs, functions, references, and ports
with placeholders such as `"[PID]"`, and they replace the values of sensitive
keys:

```elixir
{:ok, context} =
  ReqLLM.Context.new([ReqLLM.Context.user("Where is order A-1001?")])
  |> Jido.AI.Context.new()

{:ok, context} =
  Jido.AI.Context.prepare(context,
    model: "openai:gpt-4o-mini",
    options: [api_key: "sk-live-123", max_tokens: 256]
  )

snapshot = context |> Jido.AI.Context.snapshot() |> Jido.AI.Context.Snapshot.to_map()

{snapshot.content, snapshot.request.options, hd(snapshot.request.context.messages).content}
# => {:redacted, %{api_key: "[REDACTED]", max_tokens: 256}, "[REDACTED]"}
```

The redacted keys are `api_key`, `access_token`, `auth_token`,
`bearer_token`, `refresh_token`, `secret`, `password`, `authorization`,
`credential`, `cookie`, and any key ending in `_api_key`, `_secret`,
`_password`, or `_credential`.

| `content:` | Message and output content |
| --- | --- |
| `:none` | Left out. Digests and shapes only. |
| `:redacted` (default) | Replaced with `"[REDACTED]"`. |
| `:full` | Included. Use only in a trusted debugging session. |

Model attempts in the reply and the Session use `content: :none`. A failed
call stores the error's type and message, not the request body.

Telemetry follows the same rule. Jido AI events carry IDs, names, statuses,
counts, and usage. Semantic log lines leave out prompts, model output, tool
arguments, tool results, Agent state, and raw errors. The ReqLLM
OpenTelemetry bridge that Jido AI attaches records no content unless you
pass `req_llm: [content: ...]`; see
[Telemetry and Tracing](telemetry-and-tracing.livemd).

## Portable State

Agent state, `Jido.Session`, and `Jido.Thread` hold only data: maps, lists,
strings, numbers, atoms, and booleans. A durable Agent saves them, and a
thawed Agent continues from them. A process, task, stream, callback, or
provider client can't survive that round trip, so Jido AI rejects them where
they enter:

```elixir
session = Jido.Session.new(id: "session:support-1")

Jido.Session.put_metadata(session, %{tenant: "acme"}).metadata
# => %{tenant: "acme"}

Jido.Session.put_metadata(session, %{owner: self()})
# ** (ArgumentError) invalid session metadata
```

Tool source specs follow the same rule:

```elixir
Jido.AI.ToolSource.load(%{jido_ai_tool_sources: [{MyApp.HelpCenterTools, %{owner: self()}}]})
# => {:error, {:nonportable_tool_source, [:tool_source, 1, :owner]}}
```

Keep live resources in your application, and store their names or IDs. A
tool source config such as `%{tenant: "acme"}` names a tenant. The source
finds its client at call time.

Request data must be portable too. A function in `options` fails the
request with `{:error, %ArgumentError{}}` before the model call.

## Idempotent Effects

Two things in a request can run more than once: a Context transformation
when a step replays, and a tool when the model calls it again.

### Context Operations

`Jido.AI.Context.transform/3` takes a stable operation ID. A second call
with the same ID returns the Context unchanged and doesn't run the function:

```elixir
{:ok, context} =
  ReqLLM.Context.new([ReqLLM.Context.user("Refund $80 on order A-1001.")])
  |> Jido.AI.Context.new()

add_policy = fn req_context ->
  policy = ReqLLM.Context.system("Refunds over $50 need a supervisor.")
  %{req_context | messages: [policy | req_context.messages]}
end

{:ok, context} = Jido.AI.Context.transform(context, "policy:refund-limit:v1", add_policy)
{:ok, context} = Jido.AI.Context.transform(context, "policy:refund-limit:v1", add_policy)

length(context.request.context.messages)
# => 2
```

Derive the ID from what the change means, such as a policy name and version,
not from a timestamp. [Context Lifecycle](context-lifecycle.md) covers the
rest of the lifecycle.

### Side-Effecting Tools

The model can call `issue_refund` twice in one request, and a client can
resend the same request Signal. Two habits make that safe:

1. Derive an idempotency key from stable data. `context.signal.id` is the
   request ID, the same value as `reply.data.request_id`.
2. Return the effect as a Directive. On an Agent Server it runs after the
   Turn commits, so a request that fails later never sends it.

```elixir
defmodule MyApp.IssueRefund do
  use Jido.Action,
    id: "my_app/actions/issue_refund",
    vsn: 1,
    name: "issue_refund",
    description: "Refund part or all of one order.",
    schema: Zoi.object(%{order_id: Zoi.string(), amount_cents: Zoi.integer(gte: 1)})

  @impl Jido.Action
  def run(%{order_id: order_id, amount_cents: amount_cents}, context) do
    key = "refund:#{context.signal.id}:#{order_id}"

    refund =
      Jido.Agent.Directive.emit("my_app.refund.requested", %{
        order_id: order_id,
        amount_cents: amount_cents,
        idempotency_key: key
      })

    {:ok, %{order_id: order_id, status: "requested"}, [refund]}
  end
end

defmodule MyApp.SupportAgent do
  use Jido.AI.Agent, id: "my_app/support_agent", vsn: 1, name: "support_agent"

  ai do
    reasoning Jido.AI.Reasoning.ReAct do
      model "openai:gpt-4o-mini"
    end

    tools do
      action MyApp.LookupOrder
      action MyApp.IssueRefund
    end
  end
end
```

Run one request offline:

```elixir
MyApp.OfflineModel.respond_with([
  MyApp.OfflineModel.tool_call("issue_refund", %{order_id: "A-1001", amount_cents: 500}),
  MyApp.OfflineModel.text("I requested a $5.00 refund for order A-1001.")
])

agent = MyApp.SupportAgent.instantiate!(id: "support-1")

signal =
  MyApp.SupportAgent.request_signal!(%{
    input: "Refund $5 on order A-1001.",
    options: MyApp.OfflineModel.options()
  })

{:ok, _agent, [%Jido.Agent.Directive.Emit{signal: refund}, %Jido.Agent.Directive.Reply{signal: reply}]} =
  MyApp.SupportAgent.cmd(agent, signal)

{refund.type, refund.data.idempotency_key == "refund:#{reply.data.request_id}:A-1001"}
# => {"my_app.refund.requested", true}

hd(reply.data.tool_attempts).effects_count
# => 1
```

`cmd/3` returns the `Emit` as data and sends nothing. An Agent Server
dispatches it after commit. The service that moves money rejects a second
request with the same key.

The key covers repeats inside one request and resends of the same Signal. A
new Signal gets a new ID. When a refund must be unique across requests, key
it on your own record, such as the support ticket ID.

For refunds above a threshold, require approval with
`tool_policy: %{review: ["issue_refund"]}`; see
[Tool Review and Cycle Limits](tool-review-and-cycle-limits.livemd).

## Next

- [Dynamic Tool Sources](dynamic-tool-sources.md) – write a trusted tool
  source.
- [Errors and Recovery](errors-and-recovery.md) – the failure shapes these
  checks return.
- [Context Lifecycle](context-lifecycle.md) – transformations, digests, and
  snapshots.
