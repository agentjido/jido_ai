# Context Lifecycle

`Jido.AI.Context` wraps one ReqLLM call. It holds the exact model, messages,
tools, and options that ReqLLM receives, the exact result that comes back,
and a record of every change in between. It knows nothing about Threads,
reasoning Flows, tools, or memory, so you can use it around any ReqLLM call.
Read [Project a Thread](project-a-thread.livemd) first if you want to know
where an AI Agent's `ReqLLM.Context` comes from.

```elixir
alias Jido.AI.Context

req_llm_context =
  ReqLLM.Context.new([
    ReqLLM.Context.system("You answer customer-support questions."),
    ReqLLM.Context.user("When will order A-1001 arrive?")
  ])

{:ok, context} = Context.new(req_llm_context, id: "ctx-support-1", metadata: %{ticket_id: "T-42"})

{:ok, context} =
  Context.transform(context, "support:order-facts:A-1001", fn req_context ->
    facts = ReqLLM.Context.system("Order A-1001: shipped, eta 2026-11-02.")
    %{req_context | messages: req_context.messages ++ [facts]}
  end)

{:ok, context} =
  Context.prepare(context,
    model: "openai:gpt-4o-mini",
    options: [
      temperature: 0.0,
      # Offline transport from "Call ReqLLM" below. Remove these three for a live provider.
      api_key: "offline-test-key",
      max_retries: 0,
      req_http_options: [plug: {Req.Test, MyApp.LLM}]
    ]
  )

%{model: model, context: llm_context, options: options} = context.request
result = ReqLLM.generate_text(model, llm_context, options)

{:ok, context} = Context.complete(context, result)

{context.stage, Enum.map(context.request.context.messages, & &1.role)}
# => {:completed, [:system, :user, :system]}
```

ReqLLM received `context.request` and nothing else. The Context keeps that
request, the result, and a digest that identifies it.

## Stages

A Context moves forward through three stages and never back:

| Stage | Set by | You can |
| --- | --- | --- |
| `:open` | `Context.new/2` | Transform the `ReqLLM.Context`. `request.model` is `nil` and `request.options` is `[]`. |
| `:prepared` | `Context.prepare/2` | Send `context.request` to ReqLLM. The request and `digest` are frozen. |
| `:completed` | `Context.complete/3` | Read `result`. Take snapshots. Nothing else changes. |

Each step returns a new value. The previous Context is unchanged.

| Field | Contents |
| --- | --- |
| `id` | Your `:id`, or a generated `"context_..."` ID. |
| `request` | `%{model:, context:, options:}`. `context` is always a valid `ReqLLM.Context`. |
| `result` | `nil`, `{:ok, %ReqLLM.Response{}}`, or `{:error, reason}`. |
| `operations` | One record per applied transformation, keyed by operation ID. |
| `digest` | SHA-256 hex of the prepared request. `nil` while open. |
| `metadata` | Your `:metadata` map, plus `:completion` after `complete/3`. |
| `created_at_ms`, `prepared_at_ms`, `completed_at_ms` | Millisecond timestamps for each stage. |

## Create

`Context.new/2` takes a `ReqLLM.Context` and these options:

| Option | Default | Effect |
| --- | --- | --- |
| `:id` | `"context_" <> generated ID` | The Context ID. Snapshots carry it as `context_id`. |
| `:metadata` | `%{}` | Your data. It isn't sent to the model. |

Anything other than a `ReqLLM.Context` returns
`{:error, :invalid_req_llm_context}`. Messages and content parts are
validated against the ReqLLM schemas here, so a bad message fails before
you prepare anything.

## Transform

`Context.transform/3` applies one function to the open `ReqLLM.Context`.
Use it for anything that edits the prompt: a retrieved fact, a customer
profile, a tool list, a trimmed history.

The function receives a `ReqLLM.Context` and returns a
`ReqLLM.Context`, `{:ok, context}`, or `{:error, reason}`.

The operation ID makes the call idempotent. A second `transform/3` with an
ID that's already recorded returns the same Context and doesn't run the
function:

```elixir
{:ok, open} = Context.new(req_llm_context)

add_greeting = fn req_context ->
  greeting = ReqLLM.Context.system("Greet the customer by name.")
  %{req_context | messages: req_context.messages ++ [greeting]}
end

{:ok, once} = Context.transform(open, "support:greeting", add_greeting)
{:ok, twice} = Context.transform(once, "support:greeting", add_greeting)

twice == once
# => true
```

Choose IDs that name the change and its input, such as
`"support:order-facts:A-1001"`. A retried step or a replayed Flow can then
call `transform/3` again without adding the fact twice. The AI Agent
runtime uses `"model-request:N"` to attach the tool list for model call `N`.

Each record in `operations` holds a digest of the `ReqLLM.Context` before
and after the function ran:

```elixir
once.operations["support:greeting"] |> Map.keys()
# => [:after_digest, :before_digest]
```

| Return | When |
| --- | --- |
| `{:ok, context}` | Applied, or the ID is already recorded. |
| `{:error, :context_not_open}` | The ID is new and the Context is prepared or completed. |
| `{:error, :context_operation_id_required}` | The ID is `""` or not a string. |
| `{:error, :invalid_req_llm_context}` | The function returned something else. |
| `{:error, reason}` | The function returned `{:error, reason}`, or the result failed ReqLLM validation. |
| `{:error, {:context_transform_failed, exception}}` | The function raised. |

## Prepare

`Context.prepare/2` freezes the request ReqLLM will receive:

| Option | Required | Effect |
| --- | --- | --- |
| `:model` | Yes | Any ReqLLM model input, such as `"openai:gpt-4o-mini"`. |
| `:options` | No, default `[]` | ReqLLM options. Must be a keyword list. |

```elixir
{:ok, prepared} = Context.prepare(open, model: "openai:gpt-4o-mini", options: [temperature: 0.0])

{prepared.stage, prepared.request.model, prepared.request.options}
# => {:prepared, "openai:gpt-4o-mini", [temperature: 0.0]}
```

The digest covers the model, every message and tool, and every option.
Two Contexts with the same request have the same digest, whatever their IDs
or metadata. Changing `temperature` from `0.0` to `0.2` changes it.

Calling `prepare/2` again with the same model and options returns the same
Context, so a retried step is safe:

```elixir
Context.prepare(prepared, model: "openai:gpt-4o-mini", options: [temperature: 0.0]) == {:ok, prepared}
# => true

Context.prepare(prepared, model: "openai:gpt-4o", options: [temperature: 0.0])
# => {:error, :context_already_prepared}
```

| Return | When |
| --- | --- |
| `{:error, :model_required}` | No `:model`. |
| `{:error, :invalid_req_llm_options}` | `:options` isn't a keyword list, such as a map. |
| `{:error, :context_already_prepared}` | Already prepared with a different request. |
| `{:error, :context_already_completed}` | Already completed. |

## Call ReqLLM

`Jido.AI.Context` doesn't call the model. Pass the three request fields to
ReqLLM yourself:

```elixir
%{model: model, context: llm_context, options: options} = context.request
result = ReqLLM.generate_text(model, llm_context, options)
```

The call isn't restricted to `generate_text/3`. The AI Agent runtime uses
the same request for `ReqLLM.stream_text/3`. Don't change the request
between `prepare/2` and the call: the digest and snapshots describe what's
in `context.request`.

To run offline, stub the provider with `Req.Test` and pass the plug in
`req_http_options`, as the opening example does. This stub returns one
OpenAI Responses API answer:

```elixir
Req.Test.stub(MyApp.LLM, fn conn ->
  Req.Test.json(conn, %{
    "id" => "resp-1",
    "object" => "response",
    "created_at" => 1,
    "model" => "gpt-4o-mini-2024-07-18",
    "status" => "completed",
    "output" => [
      %{
        "type" => "message",
        "id" => "msg-1",
        "role" => "assistant",
        "status" => "completed",
        "content" => [
          %{"type" => "output_text", "text" => "Order A-1001 arrives on 2026-11-02.", "annotations" => []}
        ]
      }
    ],
    "usage" => %{"input_tokens" => 42, "output_tokens" => 9, "total_tokens" => 51}
  })
end)
```

[Mock Model Calls with ReqLLM](mock-model-calls-with-reqllm.livemd) covers
the full mock setup.

## Complete

`Context.complete/3` attaches the exact ReqLLM result. It accepts
`{:ok, %ReqLLM.Response{}}` or `{:error, reason}`; anything else returns
`{:error, :invalid_req_llm_result}`. The request and digest don't change.

A failed call is a completed Context too. Record it the same way:

```elixir
error = ReqLLM.Error.API.Request.exception(reason: "rate limited", status: 429)

{:ok, failed} = Context.complete(prepared, {:error, error}, req_llm_request_id: "req-9")

{failed.stage, failed.metadata}
# => {:completed, %{completion: %{req_llm_request_id: "req-9"}}}
```

The third argument is completion metadata. Jido AI merges it into
`metadata.completion` and drops `nil` values. The AI Agent runtime records
`req_llm_request_id` here so a failed call still has a request ID in its
snapshot.

| Return | When |
| --- | --- |
| `{:ok, context}` | Completed, or already completed with the same result. |
| `{:error, :context_not_prepared}` | The Context is still open. |
| `{:error, :context_already_completed}` | Already completed with a different result. |
| `{:error, :invalid_req_llm_result}` | The result isn't an `{:ok, response}` or `{:error, reason}` tuple. |

## Reuse

A completed Context is final. `prepare/2` on it returns
`{:error, :context_already_completed}`. To retry, or to call a fallback
model, start a new Context from the frozen `ReqLLM.Context`:

```elixir
{:ok, retry} = Context.new(failed.request.context, metadata: %{retry_of: failed.id})
{:ok, retry} = Context.prepare(retry, model: "openai:gpt-4o", options: [temperature: 0.0])
```

`failed.request.context` already includes every transformation, so the
retry sends the same messages. The operation records stay on the first
Context.

The AI Agent runtime follows the same rule. Each model call, including
each retry and fallback, projects the Thread into a new Context. One
Context always describes one call.

## Snapshots

`Context.snapshot/2` captures a portable `Jido.AI.Context.Snapshot` at any
stage. `Context.diff/2` compares two:

```elixir
before = Context.snapshot(prepared)
later = Context.snapshot(failed)
diff = Context.diff(before, later)

{diff.before.stage, diff.after.stage, diff.before.digest == diff.after.digest}
# => {:prepared, :completed, true}

Map.take(diff, [:request_changed, :response_changed, :metadata_changed, :message_count])
# => %{
#      request_changed: false,
#      response_changed: true,
#      metadata_changed: true,
#      message_count: %{before: 2, after: 2}
#    }
```

`content:` sets how much message text a snapshot keeps:

| `content:` | Message content | Use |
| --- | --- | --- |
| `:redacted` (default) | `"[REDACTED]"` plus a content digest | Logs and request evidence |
| `:none` | Digest only | Agent state. The runtime stores this form. |
| `:full` | Complete content and tool schemas | Local debugging only |

Every form replaces values under keys such as `api_key`, `authorization`,
and `password` with `"[REDACTED]"`, and turns PIDs and functions into
placeholders. [Inspect Model Context](inspect-model-context.livemd) reads
these snapshots from a real Agent request.

## What Stays Out

`Jido.AI.Context` has no Thread, Session, Flow, tool execution, retry, or
budget logic. Those belong to:

| Concern | Owner |
| --- | --- |
| Conversation history | `Jido.Session` and `Jido.Thread`. See [Sessions and Threads](sessions-and-threads.md). |
| Choosing history for the prompt | `Jido.AI.Thread.Projection` |
| Retries, fallbacks, and budgets | The reasoning Flow. See [Budgets, Retries, and Fallbacks](budgets-retries-and-fallbacks.md). |
| Memory, retrieval, and skills | Your code, through `transform/3` |

A Context value can live in your own process or test. Store snapshots, not
the Context itself: `result` holds a full `ReqLLM.Response`, and
`request.options` can hold credentials and functions.
