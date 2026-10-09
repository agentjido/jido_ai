# Tool And Model Routing With A System One Model

You have a ReAct agent with many tools, and every turn pays for every tool schema.

After this guide, you can put a System One decision model in front of each ReAct turn so the LLM sees only the tools the next step needs, optionally on a model tier chosen per request, and you know what that bought in measured runs.

## What A System One Model Is

A System One model (TypeSafe's Jev, Cloudflare's Clef, or a self-hosted model that serves the same `/v1/systemone` wire format) takes a `state` and a map of typed questions and returns a probability for every allowed answer instead of generating text:

- `noul`: the probability that a condition holds
- `choice`: a probability per option
- `score`: a probability-weighted level on an ordered scale

Calls take roughly 100 to 200 ms and cost a small fraction of an LLM turn.

## What The Transformer Does

`Jido.AI.Reasoning.ReAct.Transformers.SystemOne` implements `Jido.AI.Reasoning.ReAct.RequestTransformer`. Before each LLM turn it asks one decision call with three questions:

- `needs_tool`: does the next step need one of the available actions?
- `tool`: which action, over every tool name plus `none`
- `depth`: one direct step, a few dependent steps, or a long chain

Then it overrides that turn:

- `tools`: the `top_k` most probable tools, never one scored at zero; no tools at all when `needs_tool` is below the threshold, so the model answers directly
- `model` (only if you configure `:models`): the fast, capable or reasoning alias by depth

Any failure (client error, raise, missing or malformed answer, more than 254 tools) returns no overrides, so the turn runs exactly as configured.

## Set It Up

Jido.AI ships the contract, `Jido.AI.SystemOne.Client`, and no HTTP client. The [`system_one_client`](https://hex.pm/packages/system_one_client) package satisfies it as-is and supports TypeSafe, Cloudflare (Clef), OpenRouter, and self-hosted endpoints:

```elixir
# mix.exs
{:system_one_client, "~> 0.1"}
```

```elixir
defmodule MyApp.ToolRouter do
  use Jido.AI.Reasoning.ReAct.Transformers.SystemOne,
    client: SystemOneClient,
    client_opts: [provider: :typesafe],
    top_k: 3
end

defmodule MyApp.SupportAgent do
  use Jido.AI.Agent,
    name: "support_agent",
    model: :fast,
    tools: [MyApp.Actions.LookupOrder, MyApp.Actions.RefundOrder, ...],
    request_transformer: MyApp.ToolRouter
end
```

To also route models by reasoning depth:

```elixir
use Jido.AI.Reasoning.ReAct.Transformers.SystemOne,
  client: SystemOneClient,
  models: {:fast, :capable, :reasoning},
  depth_thresholds: {0.75, 1.5}
```

Invalid options raise a `CompileError` at the `use` site. A request can override any of them, including per-tenant client credentials, through the runtime context key `:system_one`:

```elixir
Runner.stream(query, config, context: %{system_one: [client_opts: [api_key: tenant_key]]})
```

## Test It Without A Network

Write a client module that implements `Jido.AI.SystemOne.Client` and returns canned answers, or use `SystemOneClient.Stub`. Answers only need the documented fields:

```elixir
defmodule MyApp.FakeDecisions do
  @behaviour Jido.AI.SystemOne.Client

  @impl true
  def evaluate(_state, _questions, _opts) do
    {:ok,
     %{
       "needs_tool" => %{noul: 0.9},
       "tool" => %{probabilities: %{"lookup_order" => 0.8, "refund_order" => 0.1, "none" => 0.1}},
       "depth" => %{score: 0.3}
     }, %{latency_ms: 1}}
  end
end
```

## Observe It

Each decision emits `[:jido, :ai, :strategy, :react, :system_one_route]` with measurement `duration_ms` and metadata `request_id`, `run_id`, `iteration`, `needs_tool`, `depth`, `top_tools`, `chosen_tools` and `chosen_model` (`:unchanged` when the transformer left the field alone).

## What It Bought In Measured Runs

These numbers come from an experiment branch with the scripts and raw results ([schainks/jido, `experiments/jev_routing`](https://github.com/schainks/jido/tree/experiment/jev-tool-routing/experiments/jev_routing)). They are small, hand-built sets; measure on your own traffic before setting thresholds.

A live `Jido.AI.Agent` with 24 tools on 30 graded tasks (Jev as the decision model):

| Condition | Pass | Mean turns | Median ms | Mean input tokens | Cost per task |
| --- | --- | --- | --- | --- | --- |
| Haiku 4.5, all 24 tools | 28 / 30 | 2.03 | 1,630 | 5,603 | $0.00605 |
| Sonnet 5, all 24 tools | 30 / 30 | 2.00 | 2,621 | 6,536 | $0.01390 |
| Haiku plus this transformer (with model tiers) | 28 / 30 | 2.00 | 1,789 | 903 | $0.00210 |

- Tool gating is the cost lever: input tokens fell 6.2x at the same pass rate, and the saving grows with the number of tools.
- Model tiers did not pay on that set: the 8 two-step tasks went to Sonnet, which Haiku also passed. That is why `:models` is off by default.
- The decision call adds about 100 ms per turn.

Single-call tool selection over Jido's own 19 control actions (34 requests): Jev's `choice` plus the `noul` gate picked correctly 34 of 34 times; native tool calling on Haiku 4.5 got 27 of 34, mostly by asking for missing parameters instead of picking a tool; the best local embedding model got 24 of 29 tool requests. On 2,114 real developer requests labelled with the right tool across 17 classes, Jev zero-shot was right 58.6% of the time, and at confidence 0.7 or more it answered 39.5% of requests at 83.3% right.

Not every System One model does this task: the released CLM-v0.1-8B head scored 8 of 34 on the same tool-selection set, so benchmark the model you pick.

## Tuning Notes

- Start with `top_k: 3` and `needs_tool_threshold: 0.5`. Lower `top_k` saves more tokens and risks hiding a needed tool; the measured runs never hid one with `top_k: 3`.
- Tool descriptions are the decision model's only view of a tool. Name-plus-description was as accurate as adding parameter docs, at fewer tokens.
- Confidence is not a safety gate on its own: a terse "kill it" picked `stop_self` at 0.90 although two other actions fit. Gate destructive actions on your own policy, not on the router.
- With more than 254 tools the transformer steps aside; pre-filter with embeddings or group tools first.
