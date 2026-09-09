# 09_02 — Linear method selection and retained data APIs

[Agent example](agent.ex) ·
[Example tests](../../../test/examples/09_reasoning/09_02_method_api/09_02_method_api_test.exs)

The example builds one Agent with CoT and CoD profiles. Each profile uses its
namespace's `method/0` value. It sends real model requests through both routes,
then reads their separate committed results.

```elixir
alias Jido.AI.Reasoning.ChainOfThought

# This value goes in the same profile used by Authoring.lower/2.
reasoning = %{method: ChainOfThought.method(), model: :answer}

# Read a committed Agent snapshot; these helpers do not call a runtime.
steps = ChainOfThought.get_steps(agent, request_id)
conclusion = ChainOfThought.get_conclusion(agent, request_id)
raw_text = ChainOfThought.get_raw_response(agent, request_id)
```

ChainOfDraft has the same method and inspection helpers. Without a request ID,
select the latest retained request of that method by insertion time and stable
ID order. With an explicit ID, read only that method's matching record. Missing
records, another method's record and neutral Agent definitions return empty
steps and nil text. A pending or failed new request cannot expose an older
answer as current. An explicit older ID can still read its retained result.
These helpers read committed state. They do not return live transient deltas,
and they do not validate or convert a v2 checkpoint.

## Legacy source mapping

| Old interface | v3 interface |
| --- | --- |
| Namespace `strategy_module/0` used to select a core Strategy | Namespace `method/0` in an AI profile |
| Strategy `get_steps`, `get_conclusion`, `get_raw_response` | Same names on the namespace; old module names remain deprecated read-only adapters |
| Strategy `init/2`, `cmd/3`, `signal_routes/1`, `action_spec/1` and action atoms | Declare the AI profile and ordinary Agent routes; use native data/Builder/DSL/JSON lowering |
| Strategy `snapshot/2` | `Jido.AgentServer.agent/1` plus namespace result getters and stored request records |
| Direct CoT empty prompt normalization | Native omitted/empty instructions select the CoT prompt |
| Direct CoD omitted prompt | Native omitted instructions select the CoD prompt |
| Direct CoD explicit nil/false/empty prompt, formerly delegated to CoT | Set native instructions to `ChainOfThought.default_system_prompt()` when the old CoT fallback is required |
| Worker start/result/partial action atoms | Shared model Flow and Session runtime; no caller-managed worker event channel |

`strategy_module/0` is deprecated but still returns a loadable adapter. The
adapter supports the three old result getters. It has no init/cmd/snapshot
callbacks and is not a core v3 executor. The public CoT/CoD Agent wrappers keep
their method-specific defaults and use the shared runtime. Direct worker APIs,
CLI adapters, capability Plugins and full stored-state conversion still need
separate migration evidence.

## Retained Machine API

`Jido.AI.Reasoning.ChainOfThought.Machine` now compiles from `shared`. It keeps
new/update/to_map/from_map, prompt/parser/ID helpers, string internal statuses,
atom map statuses and the existing model-work and busy-error tuples. Stale
call IDs are ignored. Content deltas accumulate only for the active call.
Success keeps steps and conclusion; failure keeps the raw error. Terminal
states do not restart. Map conversion retains data shape; it is not a security
or version-validation boundary for checkpoints.

The Machine uses direct finite transitions instead of Fsmx. It does not own
processes or execute returned work tuples. Existing time measurements and
`[:jido, :ai, :cot, ...]` telemetry remain. The shared Usage merge retains nested
numeric counters and provider metadata. Only known keys are normalized;
arbitrary string metadata keys are not converted to atoms. The shared parser
keeps the corrections recorded in [09_01](../09_01_linear/README.md).

The actual-provider case feeds the Machine with the legacy `%{text: text,
usage: usage}` result projected from a real ReqLLM response. This adapter step
is explicit. The Machine is not a second provider or Flow implementation.

Run the seven example cases and 27 retained Machine tests:

```sh
mix test --include example --seed 0 test/examples/09_reasoning/09_02_method_api/09_02_method_api_test.exs test/jido_ai/chain_of_thought/machine_test.exs
```

The retained tests cover state transitions, parsing, deltas, usage, prompt
helpers and map round trips. The new cases add real provider input, two-method
Agent execution, loadable adapters, current-versus-retained result selection,
cancellation, raw errors, nested usage and telemetry. Root package compilation,
other methods and runtime-floor checks remain open.
