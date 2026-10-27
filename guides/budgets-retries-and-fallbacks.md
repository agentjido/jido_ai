# Budgets, Retries, and Fallbacks

A ReAct request can call the model up to 8 times and run up to 8 tools before
it stops on its own. This guide shows how to cap model calls, tool work,
elapsed time, tokens, and cost, how retries and fallback models recover from
provider errors, and what the reply looks like when a limit stops a request.
The examples use `MyApp.SupportAgent`, `MyApp.LookupOrder`, and the
`MyApp.OfflineModel` helper from [Getting Started](getting-started.livemd).

```elixir
defmodule MyApp.SupportAgent do
  use Jido.AI.Agent, id: "my_app/support_agent", vsn: 1, name: "support_agent"

  ai do
    reasoning Jido.AI.Reasoning.ReAct do
      model "openai:gpt-4o-mini"
      fallback_models ["anthropic:claude-haiku-4-5"]

      limits do
        model_calls 4
        tool_rounds 2
        retries 1
        elapsed_ms 30_000
        total_tokens 20_000
        total_cost 0.05
      end
    end

    tools do
      action MyApp.LookupOrder
    end
  end
end
```

Every value is a request default, checked against the ReAct input schema when
the module compiles. `model_calls 40` fails the build because the maximum is
16.

## The Limits

`limits` is one object in the ReAct input schema:

| Field | Default | Range | Counts |
| --- | --- | --- | --- |
| `model_calls` | `8` | `1..16` | Provider calls, including retries and fallbacks. |
| `tool_rounds` | `4` | `0..8` | Model responses whose tool calls ran. |
| `tool_calls` | `8` | `1..16` | Tool calls run in the whole request. |
| `retries` | `1` | `0..4` | Extra attempts on one model before the next fallback. |
| `elapsed_ms` | `120_000` | `1..3_600_000` | Wall time since the request started. |
| `input_tokens` | `nil` | `>= 1` | Input tokens across all model calls. |
| `output_tokens` | `nil` | `>= 1` | Output tokens across all model calls. |
| `total_tokens` | `nil` | `>= 1` | Input plus output tokens. |
| `total_cost` | `nil` | `>= 0` | Provider cost that ReqLLM reports, in USD. |
| `tool_output_bytes` | `16_384` | `256..1_000_000` | Model-visible bytes per tool result. |

`nil` turns a limit off. Unknown keys fail the request:
`unrecognized key: max_dollars, at limits`.

Chain of Thought, Tree of Thoughts, and the other single-call and multi-stage
Flows accept only `elapsed_ms`, `input_tokens`, `output_tokens`,
`total_tokens`, and `total_cost`. Their model-call count is fixed by the Flow,
and they don't retry or fall back.

## Request Overrides

A request can set `limits` for one call. The request value replaces the
Agent default for the whole field. It doesn't merge:

```elixir
{:ok, preflight} =
  MyApp.SupportAgent.preflight(%{input: "Where is order A-1001?", limits: %{retries: 0}})

Map.take(preflight.params.limits, [:model_calls, :tool_rounds, :retries, :total_cost])
# => %{model_calls: 8, tool_rounds: 4, retries: 0, total_cost: nil}
```

The Agent declared `model_calls 4` and `total_cost 0.05`. This request runs
with the schema defaults instead.

> #### Send the complete limits map {: .warning}
>
> When a request overrides `limits` or `options`, send every field you rely
> on. A partial map drops the Agent's other values, including cost and token
> caps.

## When Checks Run

`Jido.AI.Budget` checks the request before more work starts. It never
interrupts a model call or a tool that is already running.

| Point | Checks |
| --- | --- |
| Before each model call, retry, and fallback | `model_calls`, then `elapsed_ms`, tokens, and cost |
| Before each tool round | `tool_rounds`, `tool_calls`, then `elapsed_ms`, tokens, and cost |
| During each model call | `elapsed_ms` caps ReqLLM's `total_timeout` |

A limit is reached when the used amount is greater than or equal to it.
Usage counts only after a model call returns, so one call can cross a token
or cost limit. If that call asks for tools, the round doesn't start. If it
returns a final answer, the request completes.

For the provider timeout, Jido AI sets `total_timeout` to the time left in
`elapsed_ms`, or to your own `total_timeout` option when that is smaller.

## A Blocked Reply

Here the model asks for a tool after its only allowed call:

```elixir
MyApp.OfflineModel.respond_with([
  MyApp.OfflineModel.tool_call("lookup_order", %{order_id: "A-1001"})
])

agent = MyApp.SupportAgent.instantiate!(id: "support-1")

signal =
  MyApp.SupportAgent.request_signal!(%{
    input: "Where is order A-1001?",
    options: MyApp.OfflineModel.options(),
    limits: %{model_calls: 1, tool_rounds: 2}
  })

{:ok, agent, [%Jido.Agent.Directive.Reply{signal: reply}]} =
  MyApp.SupportAgent.cmd(agent, signal)

Map.take(reply.data, [:status, :reason_code, :reason, :output, :model_calls, :tool_calls])
# => %{
#      status: :blocked,
#      reason_code: :limits,
#      reason: "maximum model calls reached",
#      output: "",
#      model_calls: 1,
#      tool_calls: 1
#    }
```

The tool round ran. The check before the second model call stopped the
request. `cmd/3` still returns `{:ok, agent, [reply]}`: a stopped request is
a normal result, and the Session records it as an `:ai_request_outcome`
entry. [Project a Thread](project-a-thread.livemd) leaves a request that
didn't complete out of later model context.

Each limit has one `reason`:

| Limit | `reason` |
| --- | --- |
| `model_calls` | `maximum model calls reached` |
| `tool_rounds` | `maximum tool rounds reached` |
| `tool_calls` | `maximum tool calls reached` |
| `elapsed_ms` | `maximum elapsed time reached` |
| `input_tokens` | `maximum input tokens reached` |
| `output_tokens` | `maximum output tokens reached` |
| `total_tokens` | `maximum total tokens reached` |
| `total_cost` | `maximum total cost reached` |

`reply.data.budget` reports the request's elapsed time and the limits it ran
with:

```elixir
reply.data.budget.limits
# => %{
#      elapsed_ms: 120000,
#      model_calls: 1,
#      tool_rounds: 2,
#      tool_calls: 8,
#      input_tokens: nil,
#      output_tokens: nil,
#      total_tokens: nil,
#      total_cost: nil
#    }
```

`Jido.AI.Budget.summary/2` builds this map. `retries` and `tool_output_bytes`
are not in it.

## Retries

A failed model call returns a classified outcome instead of raising:

| Outcome | Retryable | Next step |
| --- | --- | --- |
| HTTP 408, 409, 425, 429, 500, 502, 503, 504 | yes | Retry, then fall back. |
| Timeouts and dropped connections | yes | Retry, then fall back. |
| Any other provider error | no | Fail with `reason_code: :model`. |
| A response the output guard rejects | yes | Repair, then fall back. |

Each model gets `1 + limits.retries` attempts. After a tool round, the
attempt count starts again for the next model call. Every attempt counts
toward `model_calls`, and `reply.data.retries` counts each retry and each
fallback switch.

ReqLLM has its own `max_retries` request option for HTTP retries inside one
call. Jido AI sees those as one attempt. The offline examples set it to `0`.

## Fallback Models

`fallback_models` is an ordered list. When a model's attempts run out on a
retryable error, ReAct moves to the next model with a fresh attempt count:

```elixir
rate_limited = fn conn ->
  conn
  |> Plug.Conn.put_status(429)
  |> Req.Test.json(%{"error" => %{"message" => "Rate limit reached", "type" => "requests"}})
end

Req.Test.expect(MyApp.LLM, 2, rate_limited)
MyApp.OfflineModel.respond_with([MyApp.OfflineModel.text("Order A-1001 has shipped.")])

signal =
  MyApp.SupportAgent.request_signal!(%{
    input: "Where is order A-1001?",
    options: MyApp.OfflineModel.options(),
    fallback_models: ["openai:gpt-4.1-mini"]
  })

{:ok, _agent, [%Jido.Agent.Directive.Reply{signal: reply}]} =
  MyApp.SupportAgent.cmd(agent, signal)

{reply.data.status, reply.data.model_calls, reply.data.retries}
# => {:completed, 3, 2}

Enum.map(reply.data.model_attempts, &{&1.model, &1.status})
# => [
#      {"openai:gpt-4o-mini", :error},
#      {"openai:gpt-4o-mini", :error},
#      {"openai:gpt-4.1-mini", :ok}
#    ]
```

The first model failed twice: one attempt plus one retry. The fallback
answered. The failed attempts are recorded as `:ai_model_attempt` entries,
not as conversation messages.

The example uses an OpenAI fallback so one offline plug serves all three
calls. In production, a fallback on another provider protects against one
provider's outage. Each fallback model needs its own provider key.

A non-retryable error, such as an HTTP 400, skips the fallback list. The
reply has `status: :failed`, `reason_code: :model`, and the provider message
in `reason`. [Errors and Recovery](errors-and-recovery.md) lists every
failure shape.

## Choosing Limits

| Goal | Set |
| --- | --- |
| Bound cost per request | `total_cost`, plus `total_tokens` for models ReqLLM has no price for |
| Bound latency | `elapsed_ms`, and lower `retries` |
| Stop runaway tool loops | `tool_rounds` and `tool_calls` |
| Survive provider outages | `fallback_models` on another provider |
| Keep large tool results out of the prompt | `tool_output_bytes` |

`total_cost` counts only cost that ReqLLM reports. With no price for a model,
cost stays `0` and the limit never triggers.
[Usage, Cache, and Cost](usage-cache-and-cost.md) shows where the numbers
come from.

## Next

- [Usage, Cache, and Cost](usage-cache-and-cost.md) – the usage totals that
  token and cost limits read.
- [Errors and Recovery](errors-and-recovery.md) – every blocked and failed
  reply shape.
- [Tool Review and Cycle Limits](tool-review-and-cycle-limits.livemd) –
  approve tool calls and stop repeated tool cycles.
