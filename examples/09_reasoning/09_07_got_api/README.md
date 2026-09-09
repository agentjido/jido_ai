# Public GoT helpers and graph inspection

The [Agent examples](agent.ex) and
[11 example cases](../../../test/examples/09_reasoning/09_07_got_api/09_07_got_api_test.exs)
connect public GoT authoring and inspection to the
[native graph method](../09_06_got/README.md). The macro now supplies method settings to
`Jido.AI.Agent`. It adds no execution process or command system.

```elixir
defmodule ResearchAgent do
  use Jido.AI.GoTAgent,
    name: "research",
    model: :fast,
    max_nodes: 20,
    max_depth: 5
end
```

The common `Jido.AI.Agent` macro can also select `reasoning: :graph_of_thoughts`
with `reasoning_options`. Both forms lower to the same profile and Flow.

| Public surface | Verified contract |
| --- | --- |
| `explore/2,3`, `explore_sync/2,3`, `await/1,2` | Text query, common request handle, retained text result and per-request graph |
| `strategy_opts/0` | Declared model and normalized method settings; nil phase prompts remain omitted |
| Namespace `method/0` | Returns `:graph_of_thoughts` for profile selection |
| `get_nodes/1,2`, `get_edges/1,2` | Lists from the latest or a specified retained request; pending/unknown/wrong-method requests return empty lists |
| `get_result/1,2` | Completed text result, nil for pending/unknown, or `{:error, cause}` for a failed request |
| `get_best_node/1,2`, `get_solution_path/1,2` | Retain the scored-leaf rule. A depth-limited unscored answer has no best node or solution path |
| Old Strategy module | Five deprecated read-only getters. `strategy_module/0` remains loadable but is deprecated for method selection |

Old Strategy `init`, `cmd`, `snapshot`, action atoms, schemas and signal routes
map to core Agent/Flow and Session APIs. They are not retained as a second
executor. Namespace prompt and call-ID helpers still delegate to the Machine.
Custom old command hooks and full CLI/capability mapping remain pending.

The public wrapper retains model defaults of 1024 tokens and temperature 0.2.
Explicit `llm_opts` take precedence. It retains the GoT description default,
text `last_result`, `last_prompt` and `completed` fields. `new/1` follows the
core tagged construction contract; `new!/1` returns the Agent directly.
GoT requests start fresh and do not enable history or steering.

The default public model-call budget is `min(2 * max_nodes, 10_000)`, or 40
with default settings. `max_iterations` can set a smaller limit. A 14-call search
with ten generated thoughts and four connection calls proves that a valid
search is not stopped at the generic ten-call default. It retains all 210
tokens and stops at the declared node budget. The common 60-second request
deadline and provider timeout options still apply.

While a new request is pending, its result is nil and graph getters are empty.
A specified earlier request ID can still read a completed graph. Failed
requests retain the explored graph, measured usage and original cause in the
request record. The namespace exposes the error pair. Public `last_result`
holds a printable error, without duplicating the whole failed graph as text.
Cancellation keeps its supplied reason and completed call usage; a later
search can start. Active graph inspection and durable resume remain open.

The path example found an infinite parent-cycle traversal in the old Machine.
Path inspection now skips a cyclic parent chain and tries the next parent. It
keeps a valid path when one exists and returns an empty list when all parent
chains cycle. Existing acyclic traversal behavior remains covered by the
retained Machine tests.

The admission example also found two forms of busy rejection: core could refuse
before a turn, or Start could refuse after reading the pending request. The
shared request API now returns `{:error, :busy}` for both and sends `:busy` in
the rejected request's stream event. No second request record is stored. Other
typed admission errors and duplicate-ID behavior stay intact. Direct core
errors are not rewritten by this helper. Method identity on an admission-failure
event remains a separate observation gap; its legacy constructor defaults to
ReAct before a request job exists.

Distinct voting/weighted algorithms, general branching, aggregation across
several leaves, typed/rich contracts, runtime state overrides, full provider
variants, CLI/capability paths, state conversion and package checks remain
required. This profile does not close the full method or API audit.

Run from the repository root:

```sh
mix test --include example --seed 0 test/examples/09_reasoning/09_07_got_api/09_07_got_api_test.exs
```

All 11 cases are excluded by default and use the one shared MockLLM server.
