# Public TRM helpers on v3

The [Agent examples](agent.ex) and
[12 example cases](../../../test/examples/09_reasoning/09_09_trm_api/09_09_trm_api_test.exs)
port `use Jido.AI.TRMAgent` through the common `Jido.AI.Agent` lowerer. They use
the native TRM method from [09_08](../09_08_trm/README.md), the same Flow, Session and mock.

```elixir
defmodule MyApp.ReviewAgent do
  use Jido.AI.TRMAgent,
    name: "review_agent",
    model: :fast,
    max_supervision_steps: 5,
    act_threshold: 0.9
end

{:ok, request} = MyApp.ReviewAgent.reason(server, "Review this answer")
{:ok, answer} = MyApp.ReviewAgent.await(request)
```

`reason/2,3`, `reason_sync/2,3`, `await/1,2` and `strategy_opts/0` remain
available. Both reason helpers retain their text-only guards. The inherited
common Agent API adds `ask`, `ask_sync`, `ask_stream` and cancellation. Tests
verify streaming phase events, one selected-answer terminal result, cancellation
during improvement, busy rejection, retained usage and a later request.

The default model remains `:fast`. The real mock request checks its configured
alias resolution. Generation defaults remain 1024 tokens and temperature 0.2.
Explicit `llm_opts` take precedence over those generation fields. Native
`system_prompt` instructions precede all required phase prompts. Method options
retain the defaults and validation from 09_08. The default description is
`"TRM agent <name>"`.

The wrapper sets its call and iteration budget to three times the maximum
supervision steps, capped at the common 10,000 limit. An explicit
`max_iterations` takes precedence. One example completes all five cycles and
15 model calls, storing 225 tokens. Another stops at two calls and retains
the reviewed answer for inspection without a successful domain result.

## State and inspection

Core `new/1` returns `{:ok, agent}`; `new!/1` returns the Agent value. The
common Session owns request records. The pure compatibility projection supplies
`last_prompt`, string `last_result` and `completed`. Admission clears the latest
convenience result. Completion stores the selected answer. Failure retains the
printable method result while the request record and `await` keep the canonical
cause. The model field remains a declared value; runtime state overrides still
need their own migration contract.

At a completed cycle boundary, the selected answer is the latest improvement.
It can be newer than the highest reviewed `best_answer`. The inspection helpers
keep both values so that a caller can compare the emitted result with the last
scored result.

`Jido.AI.Reasoning.TRM` now exposes these retained-data helpers:

| Helper | Retained value | No data |
| --- | --- | --- |
| `get_answer_history/1,2` | Improved answers | `[]` |
| `get_current_answer/1,2` | Latest answer, which can be unreviewed | `nil` |
| `get_confidence/1,2` | Latest review confidence | `0.0` |
| `get_supervision_step/1,2` | Number of the current cycle | `0` |
| `get_best_answer/1,2` | Highest scored answer | `nil` |
| `get_best_score/1,2` | Highest review score | `0.0` |

The optional second argument selects a request ID. Completed and failed records
can retain method data. Pending, unknown and other-method records return the
empty values. An older completed record remains available while a new request
is pending. The tests use actual requests to verify these distinctions.

The old `TRM.Strategy` name remains loadable for deprecated versions of the six
getters and three prompt helpers. Its execution callbacks and action atoms are
removed. `TRM.method/0` supplies `:trm` for profile selection. Call-ID generation
and the three default prompt functions retain their supported names.

## Mapping and open gates

| Old role | V3 role |
| --- | --- |
| Strategy initialization and command loop | Shared profile and Flow |
| `on_before_cmd` request tracking | Common admission Action and candidate projection |
| `on_after_cmd` result tracking | Common settlement and candidate projection |
| `__strategy__` method state | Retained request method data; active inspection still needs a port |
| Strategy model directives | Shared model operation and owned request task |
| Strategy getters | Deprecated delegates to retained request inspection |

This step does not add a general adapter for old command callbacks or external
phase-result Signals. The common runtime owns phase correlation. Custom hooks,
legacy phase-input/state conversion, runtime overrides, CLI/capability APIs,
active phase inspection, complete provider/media behavior and durable recovery
remain required. Typed results, rich queries, tools and steering retain the
explicit native limits. The shared admission-failure method-identity issue
from [09_07](../09_07_got_api/README.md) is also open. Root dependency, package, consumer,
minimum-runtime and rollback gates remain open.
