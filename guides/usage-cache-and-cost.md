# Usage, Cache, and Cost

Every reply carries token counts, prompt-cache reads and writes, and provider
cost for the whole request, plus the same facts for each model call. This
guide shows where each number lives, how Jido AI adds them up, and how to ask
a provider to cache the prompt. The examples use `MyApp.LookupOrder` and the
`MyApp.OfflineModel` helper from [Getting Started](getting-started.livemd).

```elixir
reply.data.usage
# => %{
#      input_tokens: 2500,
#      output_tokens: 50,
#      total_tokens: 2550,
#      cache_read_tokens: 1024,
#      cache_write_tokens: 0,
#      cache_write_tokens_by_ttl: %{},
#      reasoning_tokens: 0,
#      compute_units: 0,
#      input_cost: 2.98e-4,
#      output_cost: 3.0e-5,
#      total_cost: 3.28e-4,
#      input_includes_cached: true,
#      input: 2500,
#      output: 50,
#      cached_tokens: 1024,
#      cache_creation_tokens: 0
#    }
```

## Where Numbers Come From

ReqLLM owns provider usage. It reads each provider's response, normalizes the
token fields, and prices the call from its model catalog. Jido AI doesn't
count tokens or keep a price list. `Jido.AI.Usage` takes ReqLLM's normalized
usage and keeps request totals.

| Place | Scope | Built by |
| --- | --- | --- |
| `reply.data.usage` | The whole request | `Jido.AI.Usage.add/2` over every model call |
| `reply.data.model_attempts[i].outcome.usage` | One model call | ReqLLM, then `Jido.AI.Usage.normalize/1` |
| `reply.data.model_attempts[i].prompt_cache` | One model call | `Jido.AI.Usage.cache_observation/3` |
| `:ai_request_outcome` Thread entry | The whole request | The same map as `reply.data.usage` |
| `:ai_model_attempt` Thread entries | One model call | The same map as each attempt |

A failed model call adds zero usage. Retries and fallbacks each add their own
call.

## Run a Request

The offline replies report usage the way the OpenAI Responses API does. The
second call reads 1,024 cached input tokens:

```elixir
defmodule MyApp.SupportAgent do
  use Jido.AI.Agent, name: "support_agent", id: "my_app/support_agent", vsn: 1

  ai do
    reasoning Jido.AI.Reasoning.ReAct do
      model "openai:gpt-4o-mini"

      prompt_cache do
        enabled true
      end
    end

    tools do
      action MyApp.LookupOrder
    end
  end
end

with_usage = fn body, input, cached, output ->
  Map.put(body, "usage", %{
    "input_tokens" => input,
    "input_tokens_details" => %{"cached_tokens" => cached},
    "output_tokens" => output,
    "total_tokens" => input + output
  })
end

MyApp.OfflineModel.respond_with([
  MyApp.OfflineModel.tool_call("lookup_order", %{order_id: "A-1001"}) |> with_usage.(1_200, 0, 20),
  MyApp.OfflineModel.text("Order A-1001 has shipped.") |> with_usage.(1_300, 1_024, 30)
])

agent = MyApp.SupportAgent.instantiate!(id: "support-1")

signal =
  MyApp.SupportAgent.request_signal!(%{
    input: "Where is order A-1001?",
    options: MyApp.OfflineModel.options()
  })

{:ok, agent, [%Jido.Agent.Directive.Reply{signal: reply}]} =
  MyApp.SupportAgent.cmd(agent, signal)

Map.take(reply.data.usage, [:input_tokens, :output_tokens, :cache_read_tokens, :total_cost])
# => %{input_tokens: 2500, output_tokens: 50, cache_read_tokens: 1024, total_cost: 3.28e-4}
```

## Request Totals

`reply.data.usage` sums these counters across calls:

| Field | Meaning |
| --- | --- |
| `input_tokens`, `output_tokens`, `total_tokens` | Prompt, completion, and both. |
| `cache_read_tokens` | Input tokens the provider served from its prompt cache. |
| `cache_write_tokens` | Input tokens the provider wrote to its prompt cache. |
| `cache_write_tokens_by_ttl` | Cache writes grouped by TTL, such as `%{"5m" => 80}`. |
| `reasoning_tokens` | Hidden reasoning tokens the provider reported. |
| `compute_units` | Non-token billing units, when a provider reports them. |
| `input_cost`, `output_cost`, `total_cost` | USD cost that ReqLLM priced. |

`input`, `output`, `cached_tokens`, and `cache_creation_tokens` are aliases
for `input_tokens`, `output_tokens`, `cache_read_tokens`, and
`cache_write_tokens`.

`input_includes_cached` says how to read `cache_read_tokens`. `true` means
`input_tokens` already includes the cached tokens, as with OpenAI: this
request sent 2,500 input tokens and 1,024 of them came from cache. `false`
means the provider reports cached tokens separately. `:mixed` means the
request's calls disagreed, which can happen when a fallback model uses
another provider.

## Per-Attempt Usage

Each model attempt keeps its own normalized usage:

```elixir
Enum.map(reply.data.model_attempts, fn attempt ->
  Map.take(attempt.outcome.usage, [:input_tokens, :cache_read_tokens, :total_cost])
end)
# => [
#      %{input_tokens: 1200, cache_read_tokens: 0, total_cost: 1.92e-4},
#      %{input_tokens: 1300, cache_read_tokens: 1024, total_cost: 1.36e-4}
#    ]
```

Attempt usage is ReqLLM's full normalized map. It has fields the request
total doesn't, such as `reasoning_cost`, `usage_reported`, and
`billing_usage_complete`. Read these per attempt when you reconcile a bill.

## Cost

ReqLLM prices each call from its model catalog, including the lower price for
cached input. The second call above cost less per input token than the first
because 1,024 of its tokens were cache reads.

Cost is `0` in the totals when ReqLLM has no price for the model.
`limits.total_cost` reads `usage.total_cost`, so it can't stop a request on
an unpriced model. Add `limits.total_tokens` for those models; see
[Budgets, Retries, and Fallbacks](budgets-retries-and-fallbacks.md).

## Prompt Caching

`prompt_cache` asks the provider to cache the stable prefix of the prompt:
instructions, tool definitions, and earlier conversation.

| Field | Default | Meaning |
| --- | --- | --- |
| `enabled` | `false` | Send provider cache options. |
| `ttl` | none | A string such as `"5m"` or `"1h"`, or milliseconds. |

Jido AI lowers it to the provider's options:

| Model prefix | Provider options sent |
| --- | --- |
| `openai:` | `prompt_cache_key` set to the Session ID, and `prompt_cache_options: %{ttl: ttl}` when `ttl` is set |
| `anthropic:` | `anthropic_prompt_cache: true`, and `anthropic_prompt_cache_ttl` when `ttl` is set |
| `amazon_bedrock:`, `bedrock:` | `prompt_cache: true`, and `prompt_cache_ttl` when `ttl` is set |
| any other | nothing |

The Session ID as the OpenAI cache key keeps one conversation's requests on
the same cache entry.

Each attempt records what the provider reported:

```elixir
Enum.map(reply.data.model_attempts, &Map.take(&1.prompt_cache, [:requested, :read_tokens, :write_tokens]))
# => [
#      %{requested: true, read_tokens: 0, write_tokens: 0},
#      %{requested: true, read_tokens: 1024, write_tokens: 0}
#    ]
```

| Field | Meaning |
| --- | --- |
| `requested`, `requested_ttl` | What this request asked for. |
| `read_tokens`, `write_tokens` | Cache tokens the provider reported for this call. |
| `write_tokens_by_ttl` | Writes grouped by TTL, when the provider groups them. |
| `writes` | One entry per TTL with `ttl_ms` and `estimated_expires_at_ms`. |
| `observed_at_ms` | When the call completed. |

`estimated_expires_at_ms` is `observed_at_ms` plus the TTL. The provider
doesn't confirm it. A later read can extend the entry, and the provider can
evict it early.

`Jido.AI.Usage.cache_observation/3` builds the same map from any usage value:

```elixir
Jido.AI.Usage.cache_observation(
  %{enabled: true, ttl: "5m"},
  %{input_tokens: 2_000, cache_write_tokens: 1_536},
  1_000
)
# => %{
#      requested: true,
#      requested_ttl: "5m",
#      observed_at_ms: 1000,
#      read_tokens: 0,
#      write_tokens: 1536,
#      write_tokens_by_ttl: %{},
#      writes: [
#        %{ttl: "5m", ttl_ms: 300000, token_count: 1536,
#          observed_at_ms: 1000, estimated_expires_at_ms: 301000}
#      ]
#    }
```

When a provider reports writes without a TTL, the observation uses the
requested TTL.

## Add Usage Yourself

Use `Jido.AI.Usage` to total usage across requests, such as one customer's
conversation:

```elixir
Jido.AI.Usage.zero()
|> Jido.AI.Usage.add(%{input_tokens: 1_200, output_tokens: 40, cache_read_tokens: 1_024})
|> Jido.AI.Usage.add(%{input_tokens: 1_300, output_tokens: 25, cache_read_tokens: 1_024})
|> Map.take([:input_tokens, :output_tokens, :total_tokens, :cache_read_tokens])
# => %{input_tokens: 2500, output_tokens: 65, total_tokens: 2565, cache_read_tokens: 2048}
```

`add/2` normalizes each value through ReqLLM first, so provider-shaped maps
work. It derives `total_tokens` when the input has none.

## Usage in Telemetry

The `[:jido, :ai, :agent, :stop]` event carries the request totals as
measurements: `input_tokens`, `output_tokens`, `cache_read_tokens`,
`cache_write_tokens`, `reasoning_tokens`, and `total_cost`.
`Jido.AI.Telemetry.metrics/0` also sums the same fields per provider and model
from ReqLLM's `[:req_llm, :request, :stop]` event, as
`jido.ai.model.input_tokens` and so on.
[Telemetry and Tracing](telemetry-and-tracing.livemd) attaches to both.

## Next

- [Budgets, Retries, and Fallbacks](budgets-retries-and-fallbacks.md) – stop
  a request on tokens or cost.
- [Inspect Model Context](inspect-model-context.livemd) – read the Context
  snapshots stored with each attempt.
- [Telemetry and Tracing](telemetry-and-tracing.livemd) – export usage as
  metrics.
