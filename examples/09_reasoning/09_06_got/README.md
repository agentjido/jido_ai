# Graph of Thoughts through the shared Flow

The [Agent example](agent.ex) and
[22 example cases](../../../test/examples/09_reasoning/09_06_got/09_06_got_test.exs) run the
existing GoT method through core Agent, Flow, Exec and the common Session.
All model replies use the same MockLLM server as the other examples.

```elixir
ai :assistant do
  models do
    model(:answer, "openai:gpt-4o-mini")
  end

  reasoning :graph_of_thoughts do
    model(:answer)
    options(max_nodes: 20, max_depth: 5, min_nodes_for_aggregation: 3)
  end

  requests do
    mode(:session)
    streaming(true)
  end

  result(nil, into: :reply)
end
```

Declare the `:reply` domain field and route as shown in the Agent example.
DSL, source data, Builder and registered source JSON produce the same definition.
Direct Flow and ordinary Agent turns run the same method. Successful output
remains a string. Completed request metadata stores the graph under
`meta.reasoning.graph`, including nodes, edges, status, settings, result and
usage. There is no separate GoT executor or runtime process.

| Setting | Default | Contract |
| --- | --- | --- |
| `max_nodes` | 20 | Positive node budget, including the root and aggregate |
| `max_depth` | 5 | Positive depth limit for generated thoughts |
| `min_nodes_for_aggregation` | 3 | Positive threshold from the existing Machine environment, now exposed as native method data |
| `aggregation_strategy` | `:synthesis` | Selects distinct synthesis, voting, or weighted aggregation instructions |
| `generation_prompt` | nil | Explicit phase prompt, then profile instructions, then the Machine default |
| `connection_prompt`, `aggregation_prompt` | nil | Explicit phase prompt, else the Machine default |

Generation defaults are 1024 tokens and temperature 0.2. Declared model options
override them. The example tests both streaming and non-streaming requests.
Common model-call, iteration and total-duration limits still apply. A root-only
budget fails before a model request. A call limit between phases retains the
graph and measured usage without a domain result write.

The baseline algorithm usually generates two thoughts, then synthesizes the
current leaf. It can find connections when aggregation is deferred. The
connection case uses the new threshold option to exercise that existing phase.
The mock reads the node IDs in the actual provider request and returns a real
connection. The next generation receives each reachable ancestor once. Unknown
node IDs are ignored by the retained connection parser.

The Machine uses `aggregation_strategy` to select synthesis, voting, or weighted
instructions for the aggregation model call. The example checks the actual
provider prompt for each setting. The model performs the selected strategy;
there is no separate deterministic voting engine. Default runs also do not
demonstrate general branching or aggregation across several leaves. Those
behaviors need explicit examples and implementation before full method
acceptance. Core Flow remains the composition layer.

The old Strategy also preferred the Machine's default phase prompts over
configured prompt options. Native v3 now honors explicit prompts. The connection
example checks all three phase prompts at the provider. This is an explicit
correction to the old option behavior.

The [Machine](../../../lib/jido_ai/shared/got_machine.ex) keeps its module name
and data helpers. Finite transitions replace Fsmx. All 41 retained Machine tests
run unchanged on v3 dependencies. Extra examples cover a diamond, a disconnected
node, root/leaf traversal and a cycle without duplicate reachable IDs. A cycle
can make its starting node reachable; that existing result is retained. This
covers the graph change in PR 314 without making incidental traversal order a
sorting guarantee.

Usage uses the shared nested-metadata merger. Missing per-call totals are
derived before accumulation. The Machine retains legacy lifecycle telemetry
by default. Native execution disables those duplicate events and uses common
phase events, typed Signals and telemetry with the `:got` label. Each model call
has separate call and phase IDs under one request.

Output rejection, an empty length-limited response and a model-call limit retain
graph failure data. Cancellation and owner loss stop active transport and allow
a new request. The total deadline also stops a held connection. Request helpers
now normalize busy rejection to `{:error, :busy}` as recorded in
[09_07](../09_07_got_api/README.md). Tool declarations and steering
are invalid for this method. Request transforms cannot add tools back, and an
unsolicited tool call fails before execution.

Typed GoT output and rich input remain explicit unsupported contracts. The
[09_07 example](../09_07_got_api/README.md) adds public GoTAgent helpers and retained
namespace/Strategy inspection mapping. Runtime state overrides, CLI and
capability entry points, full provider/failure variants, active graph inspection,
durable resume and root package checks remain pending. This example does not
complete the API or history audit.

Run from the repository root:

```sh
mix test --include example --seed 0 test/examples/09_reasoning/09_06_got/09_06_got_test.exs
```

These 22 cases are excluded by default. The added MockLLM request-based reply
contract stays in the default suite. Its callback runs in the connection worker,
receives the decoded provider body and returns an ordinary scripted reply.
It does not alter the Agent or fabricate tool execution.
