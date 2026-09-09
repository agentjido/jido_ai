# 09_04 — Tree of Thoughts through core Flow

[Agent example](agent.ex) ·
[Example tests](../../../test/examples/09_reasoning/09_04_tot/09_04_tot_test.exs)

This example ports the native `:tree_of_thoughts` profile. Each request generates
thoughts, evaluates them, selects a branch and repeats until a search limit or
completion rule applies. The common Flow runs every model and tool call. The
search model stores data and returns the next phase; it owns no process.

```elixir
agent do
  ai :assistant do
    models do
      model :answer, "openai:gpt-4o-mini"
    end

    reasoning :tree_of_thoughts do
      model :answer
      options branching_factor: 2,
              max_depth: 3,
              traversal_strategy: :best_first,
              top_k: 3,
              min_depth: 2,
              max_nodes: 100,
              beam_width: 4,
              max_parse_retries: 1,
              max_tool_round_trips: 3
    end

    requests do
      mode :session
      streaming true
    end

    result nil, into: :reply
  end
end
```

Use the common `tools`, `controls` and model generation options. Generation and
evaluation can both request tools. A tool follow-up stays in its current search
phase. The round limit applies to that phase call. Each actual provider request
has a new call ID; phase IDs group its tool follow-ups. Canonical events, typed
Signal metadata and telemetry retain phase identity. Only the whole search
completes the request. Common usage accounting includes all calls once.

The result retains `best`, ranked `candidates`, `termination`, `tree`, `usage`
and `diagnostics`. Candidate paths include the original problem. Request
metadata also retains nodes and the selected path. Output controls receive the
whole result before a domain state write. Failure results retain diagnostics,
structured causes and measured usage. The compatibility status strings remain
`"completed"` and `"error"`.

| Rule | Execution evidence |
| --- | --- |
| BFS, DFS and best-first | Different selected paths through six real calls |
| Minimum depth, threshold and convergence | No early threshold before minimum depth; flat search stops |
| Node and branch limits | Excess thoughts are removed before evaluation; the root counts toward the node limit |
| Beam and top-k | Best-first frontier and ranked output obey their separate limits |
| Search duration | A held response reaches the search budget; evaluation returns the best candidate |
| Request deadline | The common deadline stops the active transport; it is separate from the search stop rule |
| Parser repair | One bounded model repair, no advertised tools, complete usage and failure diagnostics |
| Legacy parsing | Numbered thoughts and default evaluation scores still work |
| Tools and callbacks | Before hook precedes validation; after hook transforms results; reverse completion preserves call order |
| Request failure and recovery | No failed domain write; cancellation and owner loss allow a later request |
| Authoring | DSL, data, Builder and registered source JSON produce the same definition; direct Flow returns the same result contract |

ReqLLM can return streamed JSON as a decoded object with no text. The adapter
reads that object. It does not turn an empty text field into a parser failure.
The JSON-first parser retains the legacy numbered-text fallback and positional
`t1`, `t2` score keys. Unspecified scores still receive 0.5. This is the retained
parser behavior; it is not strict score validation.

A complete decoded object can survive a provider `length` finish reason even
when ReqLLM clears its text field. Generation and evaluation still pass through
the method parser. An invalid object uses bounded parser repair. An empty
length-limited evaluation fails, retains usage and permits a later request.
This does not prove successful recovery from a disconnected transport.

`max_duration_ms` is a search stop rule checked after evaluation. Use the common
`controls.timeout` for a hard request deadline. A root-only `max_nodes: 1`
budget fails without a provider call because it cannot produce a candidate.
The port also fixes node-limit overshoot: a generated batch cannot add more
nodes than the remaining capacity. Branch limits now bound returned thoughts,
including a provider response with too many entries.

The [Machine](../../../lib/jido_ai/shared/tot_machine.ex) and
[Result](../../../lib/jido_ai/shared/tot_result.ex) keep their module names.
Finite transitions replace Fsmx. Usage uses the shared nested-metadata merge.
The compatibility Machine still emits its legacy telemetry by default; the
native adapter disables it and uses the common observation path.

Current limits are explicit. Native ToT accepts text queries and rejects
steering and a declared typed result schema. The later
[09_05 example](../09_05_tot_api/README.md) ports public helpers, retained namespace
getters, Strategy inspection mapping and the PR 347 alias workflow. CLI and
capability entry points, live tree inspection, full provider failure variants,
state conversion and checkpoint resume remain separate gates. The root package
still has v2 dependencies.

Run `mix test --include example --seed 0 test/examples/09_reasoning/09_04_tot/09_04_tot_test.exs`
from the repository root. The 26
example cases are excluded from the default run. The 18 retained Machine
and Result cases also run against the v3 dependency set.
