# Public Tree of Thoughts and tool callbacks

The [Agent examples](../lib/examples/09_reasoning/09_05_tot_api/agent.ex) and
[28 integration cases](../test/examples/09_reasoning/09_05_tot_api_test.exs)
extend the [native ToT example](09_04_tot.md). They run the public ToT API and
the PR 347 alias workflow through the same Agent, Flow, Exec and Session.

```elixir
defmodule SearchAgent do
  use Jido.AI.ToTAgent,
    name: "search",
    model: :fast,
    max_depth: 3,
    branching_factor: 3,
    tools: [FindDocument, ReadDocument]
end
```

The wrapper supplies method options to `Jido.AI.Agent`. It adds no execution
process. Native authoring still uses `reasoning :tree_of_thoughts` with an
`options` declaration. Models, controls, tools and requests use the common DSL.

| Surface | Verified behavior and v3 mapping |
| --- | --- |
| `explore/2,3`, `explore_sync/2,3`, `await/1,2` | Text input, shared request handles, complete ranked result, separate retained requests, busy rejection and cancellation with its reason |
| `best_answer/1`, `top_candidates/1,2`, `result_summary/1` | Retain the public result shape and nil-safe inspection |
| `strategy_opts/0` | Reads normalized search settings, declared model and tool policy; does not select an executor |
| Namespace `method/0` | Selects `:tree_of_thoughts` in a profile |
| Namespace getters | `get_result`, `get_nodes`, `get_solution_path` and `get_best_node` read the latest or a specified retained request |
| Old Strategy module | Keeps four deprecated, read-only getters. `strategy_module/0` is deprecated. The module has no execution callbacks |
| Old start/action/route callbacks | Use the Agent route and shared request API. Core Flow owns execution; Session owns live request work |
| Old `__strategy__` state | Completed metadata holds method results, nodes and paths. Failed results retain explored nodes and causes. Active tree inspection and durable conversion remain pending |

The public wrapper retains generation defaults of 1024 tokens and temperature
0.2. Explicit `llm_opts` override those defaults. Tools are optional. Each
request starts a new search; ToT does not enable steering or conversation history.
The public default model-call budget is
`min(2 * max_nodes * (max_tool_round_trips + 1) + 2 * max_parse_retries, 10_000)`.
It is 802 with default search settings. The public default tool-call budget is
10,000. `max_iterations` and `max_tool_calls` can set smaller limits. These are
finite v3 request limits. Native profiles keep the common control defaults and
must declare enough calls for their search. A real 16-call example proves that
the public wrapper can complete a search with 12 tool calls.

`max_duration_ms` remains a search stop check after evaluation. For public ToT
compatibility it also supplies the provider timeout, as the v2 Directive did.
An explicit `llm_timeout_ms` can change that timeout. Model generation options
and request context keep the common precedence rules. A held SSE response proves
that the provider call stops and the failed search remains readable. The common
total request deadline defaults to 60 seconds; `request_timeout_ms` changes it.
The native DSL uses `controls.timeout` for that hard request deadline.

The alias example runs real list and consume Actions. The result callback
replaces a long key with `item-1` and proposes an alias-state effect. The next
before callback restores the original key before Action validation. The model
sees the short key. The Agent commits the alias state only when the full search
completes. The same Actions still accept original keys through direct core Exec,
which does not invoke AI callbacks. An ordinary Agent turn proves the same alias
behavior and complete state commit without a request session.

Runtime tool context uses the authoritative state snapshot from before request
admission, then applies permitted staged effects. It does not use later public
`last_prompt` projection as the tool snapshot. Request tool context can override
declared tool context; it cannot forge Agent identity or request identity.

Core Exec returns each raw final retry result to `after_tool_call`. The shared
path then filters effects, updates the candidate and creates the model input
and canonical tool result. The old inbound `ai.tool.result` was execution
control in v2. In v3, typed Signals observe work; they do not run a second tool
executor. Tests cover before-callback errors, interruptions, invalid returns,
exceptions, throws, exits and identity changes. They also cover after-callback
errors, invalid returns, exceptions, throws and exits. A later callback failure
retains completed tool evidence but does not commit earlier staged state.
Actual Action I/O cannot be undone by that failure.

Getters read retained results. While the latest request is pending, its result
is nil and its nodes are empty. A specified earlier request ID can still read a
completed tree. Live frontier inspection, typed ToT results, rich input, runtime
model/state overrides, full provider failure variants, CLI/capability entry
points, old command-hook mappings and durable resume remain migration gates.
This example does not close the full API or history audit.

From `examples/v3`, run:

```sh
mix test --include integration --seed 0 test/examples/09_reasoning/09_05_tot_api_test.exs
```

The integration cases remain excluded by default. All model replies come from
the one shared MockLLM HTTP/SSE server. Root dependencies remain on v2.
