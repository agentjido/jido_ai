# Budgets and quotas

Controls bound one request. A quota can govern use across requests or across
an application scope. Keep these separate. `max_model_calls` counts started
model operations for one request. An HTTP retry of the same operation is not
a second model operation. A tool continuation is a new model operation. A
caller timeout does not reset counts on accepted work.

The quota Plugin can be declared in `agent do` beside the AI profile:

```elixir
agent do
  plugin Jido.AI.Plugins.Quota, config: [scope: "support", max_requests: 10]

  ai :assistant do
    model "openai:gpt-4o-mini"
    result into: :reply
  end
end
```

Choose a scope that matches the business rule. A global scope and a per-Agent
scope answer different questions. Document the reset path and the result when
the quota rejects a request. A quota check should reject before provider work
when possible. A token estimate is not the same as a final provider bill;
observed usage may arrive only after a call or stream completes.

The [quota example](../../examples/13_policy/13_01_quota/README.md) proves an
accepted request and a later rejection with the public Plugin route. The
[model-count example](../../examples/02_requests/02_20_call_counts/README.md)
shows the per-request operation count. Use those tests when you change
accounting; do not weaken a request limit to make a quota test pass. Next,
learn [observability](16_observability.md).
