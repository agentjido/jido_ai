# Tool Execution and Results

This guide covers what ReAct does between a model response with tool calls
and the next model call: validation, parallel execution, the result the model
reads, the attempt record you read, and how calls and results stay paired in
history. Read [Action Tools](action-tools.livemd) first. The examples use
`MyApp.SupportAgent` with `MyApp.LookupOrder` and the offline model helpers
from that guide.

## One Tool Round

```text
model response with tool calls
  -> guard: validate every call            (fail: repair, no tool runs)
  -> limits: tool_rounds, tool_calls, budget (fail: blocked result)
  -> review, if any call needs approval
  -> run all calls in one Parallel component
  -> record results in call order
  -> next model call
```

A round is all or nothing at validation time. If any call in a response is
invalid, none of them runs.

## Call Validation

`Jido.AI.Reasoning.Actions.GuardOutput` checks each response before any tool
runs:

| Check | Repair reason sent to the model |
| --- | --- |
| More than 4 calls in one response | `one model response can contain at most 4 tool calls` |
| Duplicate call IDs | `tool call IDs must be unique` |
| A name outside the request tool set | `model requested a tool that is not allowed` |
| Arguments fail the tool schema | `invalid tool call: {:invalid_tool_arguments, "lookup_order"}` |

`Jido.AI.Toolset.resolve_call/2` does the argument check. For an Action it
parses the arguments with the Action's Zoi schema using `coerce: true`, then
calls `validate_params/1`. `%{"order_id" => 5}` becomes
`%{order_id: "5"}`; `%{"id" => "A-1001"}` fails. Dynamic source tools
validate through their definition; see
[Dynamic Tool Sources](dynamic-tool-sources.md).

A failed check doesn't execute anything and doesn't commit the invalid
response to the conversation. ReAct calls the model again with a system
message:

```text
Repair the previous response. invalid tool call: {:invalid_tool_arguments, "lookup_order"}. Return a valid final answer.
```

Each repair spends one retry from `limits.retries` (default `1`). When retries
and fallback models are used up, the request ends with
`status: :blocked, reason_code: :output`.

## Limits Before Execution

`Jido.AI.Reasoning.ReAct.Actions.DecideNext` checks request limits before a
valid round starts:

| Limit | Default | Range | Blocked `reason` |
| --- | --- | --- | --- |
| `limits.tool_rounds` | `4` | `0..8` | `maximum tool rounds reached` |
| `limits.tool_calls` | `8` | `1..16` | `maximum tool calls reached` |

`tool_calls` counts the whole request. A round that would take the total over
the limit doesn't start. A blocked request has `reason_code: :limits`, and
none of the round's calls run. Token, cost, and time budgets are checked at
the same point; see
[Budgets, Retries, and Fallbacks](budgets-retries-and-fallbacks.md).

## Parallel Execution

`Jido.AI.Reasoning.ReAct.Actions.ExpandNext` turns a valid round into a Flow
with one Parallel component. Each call runs as its own
`Jido.AI.Reasoning.ReAct.Actions.ExecuteTool` step, named `tool_0`, `tool_1`,
and so on, with `on_error: :collect_errors`. One failing call doesn't cancel
the others.

`ExecuteTool` runs the Action with the validated params and the Agent's
Action context. It then checks the value against the Action's
`output_schema`. A raise, a throw, an `{:error, reason}`, or an output that
fails `output_schema` becomes an error outcome for that call.

`Jido.AI.Reasoning.ReAct.Actions.RecordToolResults` appends results in the
order the model listed the calls, not the order they finished.

A model asked to check `A-1001` and `A-404` in one response, where
`MyApp.LookupOrder` returns
`{:error, Jido.Action.Error.execution_error("order A-404 was not found", retry: false)}`
for the second, produces:

```elixir
Map.take(reply.data, [:status, :tool_rounds, :tool_calls, :tool_errors])
# => %{status: :completed, tool_rounds: 1, tool_calls: 2, tool_errors: 1}
```

Tool errors don't fail the request. The model reads them and decides what to
say.

## Effects

An Action tool can return `{:ok, value, directives}`. ReAct keeps the
directives and returns them from the request with the reply:

```elixir
def run(%{order_id: order_id}, _context) do
  {:ok, %{order_id: order_id, status: "shipped"},
   [Jido.Agent.Directive.emit("order.looked_up", %{order_id: order_id})]}
end

{:ok, _agent, directives} = MyApp.SupportAgent.cmd(agent, request)
Enum.map(directives, & &1.__struct__)
# => [Jido.Agent.Directive.Emit, Jido.Agent.Directive.Reply]
```

`cmd/3` returns them as data. An AgentServer runs them after it commits the
turn. Effects from a failed call are dropped. The attempt records
`effects_count`.

## What the Model Reads

`Jido.AI.ToolResult.normalize/2` turns each outcome into model content. The
model reads JSON, never Elixir terms:

| Outcome | Model content |
| --- | --- |
| `{:ok, map}` within the limit | The map, JSON-encoded |
| `{:ok, value}` over the limit | A truncation notice |
| `{:ok, value}` that isn't JSON-encodable | An `invalid_tool_result` error |
| `{:ok, %ReqLLM.ToolResult{}}` | Its content parts |
| Any error | A safe error map |

For `A-1001`, the OpenAI request carries:

```elixir
%{
  "type" => "function_call_output",
  "call_id" => "call-1",
  "output" => ~s({"eta":"2026-11-02","order_id":"A-1001","status":"shipped"})
}
```

### Error Results

An error becomes this shape, whatever the Action returned:

```elixir
%{
  "status" => "error",
  "error" => %{
    "type" => "execution_error",
    "message" => "order A-404 was not found",
    "retryable" => false
  }
}
```

`type` comes from the Jido Action error type, up to 128 bytes, with
`"tool_error"` when it's missing. `message` is capped at 1,024 bytes, with
`"tool action failed"` when it's missing. Stack traces, error details, and
`vars` never reach the model. Keep secrets out of error messages.

### Size Limit

`limits.tool_output_bytes` caps each result's JSON-encoded size. The default
is `16_384`; the range is `256..1_000_000`. A larger result is replaced, not
cut. Here an `order_history` tool returns 200 scan events, 8,416 bytes of
JSON:

```elixir
request =
  MyApp.SupportAgent.request_signal!(%{
    input: "Show the full history for A-1001",
    limits: %{tool_output_bytes: 1_024}
  })

# The model reads:
%{
  "status" => "truncated",
  "message" => "tool result exceeded the model-content limit",
  "original_bytes" => 8416,
  "max_bytes" => 1024
}
```

The model never sees a partial JSON document. If a tool can return large data,
return a summary or a page and let the model ask for more.

`Jido.AI.ToolResult.project/2` applies the same rule. Use it to test a value
against a limit:

```elixir
Jido.AI.ToolResult.project(%{note: String.duplicate("x", 300)}, 256)
# => {%{"status" => "truncated", "message" => "tool result exceeded the model-content limit",
#       "original_bytes" => 311, "max_bytes" => 256},
#     %{bytes: 311, max_bytes: 256, truncated: true}}
```

### Content Parts

Return a `ReqLLM.ToolResult` to send text, images, or files back to the model.
Set the Action's `output_schema` to `ReqLLM.ToolResult.schema()`:

```elixir
defmodule MyApp.ShippingLabel do
  use Jido.Action,
    id: "my_app/shipping_label",
    name: "shipping_label",
    description: "Return the shipping label for one order as an image.",
    schema: Zoi.object(%{order_id: Zoi.string()}),
    output_schema: ReqLLM.ToolResult.schema()

  @impl Jido.Action
  def run(%{order_id: order_id}, _context) do
    {:ok,
     %ReqLLM.ToolResult{
       output: %{order_id: order_id, label_id: "L-#{order_id}"},
       content: [
         ReqLLM.Message.ContentPart.text("The label for #{order_id} is attached."),
         ReqLLM.Message.ContentPart.image_url("https://example.com/labels/#{order_id}.png")
       ],
       metadata: %{carrier: "UPS"}
     }}
  end
end
```

The OpenAI request carries the parts as the tool output:

```elixir
"output" => [
  %{"type" => "input_text", "text" => "The label for A-1001 is attached."},
  %{"type" => "input_image", "image_url" => "https://example.com/labels/A-1001.png"}
]
```

Content, `output`, and `metadata` together share the `tool_output_bytes`
limit. An invalid content part becomes an `invalid_tool_result` error.

## Model vs Local Value

`ToolResult.normalize/2` keeps the Action's own value in `value` and the
bounded JSON in `model_content`:

```elixir
Jido.AI.ToolResult.normalize(%{status: :ok, value: %{order_id: "A-1001", status: "shipped"}})
# => %{
#      status: :ok,
#      value: %{order_id: "A-1001", status: "shipped"},
#      model_content: %{"order_id" => "A-1001", "status" => "shipped"},
#      content_parts: nil,
#      result_metadata: %{},
#      error: nil,
#      metadata: %{bytes: 40, max_bytes: 16384, truncated: false}
#    }
```

The reply, the Session, and the next model call store only the bounded model
content. When the Action produces data the model shouldn't read in full, such
as a 5 MB export, have the Action save it in your own store and return a
small reference such as `%{export_id: "EX-17", rows: 12_480}`.

## The Attempt Record

Each executed call adds one map to `reply.data.tool_attempts` and one
`:ai_tool_attempt` entry to the Session Thread:

| Field | Example |
| --- | --- |
| `tool_call_id`, `tool_name` | `"call-2"`, `"lookup_order"` |
| `tool` | `%{kind: :action, name: "lookup_order", action: "Elixir.MyApp.LookupOrder", id: "my_app/lookup_order", vsn: 1}` |
| `status` | `:ok` or `:error` |
| `input` | The model's arguments, `%{"order_id" => "A-404"}` |
| `output` | The model content shown above |
| `error` | `%{"type" => "execution_error", "message" => ..., "retryable" => false}` or `nil` |
| `content`, `result_metadata` | Content parts and `ReqLLM.ToolResult` metadata |
| `metadata` | `%{bytes: 109, max_bytes: 16384, truncated: false}` |
| `started_at_ms`, `completed_at_ms`, `duration_ms` | Wall-clock timing |
| `effects_count`, `tool_round` | `0`, `1` |
| `review` | `%{required: false, status: :not_required}` |

`reply.data` also carries `tool_rounds`, `tool_calls`, `tool_errors`, and
`tool_cycles` for the whole request.

## Call Correlation

The Session stores the assistant message with its tool calls, then one `:tool`
message per call with the matching `tool_call_id`:

```elixir
{:ok, messages} = Jido.AI.Thread.Projection.messages(agent.state.session)
Enum.map(messages, &{&1.role, Map.get(&1, :tool_call_id)})
# => [user: nil, assistant: nil, tool: "call-1", tool: "call-2", assistant: nil]
```

`Jido.AI.Thread.Projection` only projects complete exchanges. An assistant
message whose tool calls have no results, such as a request stopped by a
limit or a denied review, is left out of the next model context. Later
messages stay. Providers reject a `function_call` without its output, so this
keeps every later request valid.
[Project a Thread](project-a-thread.livemd) shows the projection rules.

## Next

- [Tool Review and Cycle Limits](tool-review-and-cycle-limits.livemd) – stop
  a round for approval and stop repeated calls.
- [Errors and Recovery](errors-and-recovery.md) – tool errors next to model,
  output, and budget failures.
- [Budgets, Retries, and Fallbacks](budgets-retries-and-fallbacks.md) – all
  request limits.
