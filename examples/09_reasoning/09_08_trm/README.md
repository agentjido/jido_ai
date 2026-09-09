# TRM through the shared Flow

The [Agent example](agent.ex) and
[24 example cases](../../../test/examples/09_reasoning/09_08_trm/09_08_trm_test.exs) run
reasoning, supervision and improvement through core Agent, Flow and Exec.
The common Session owns the request. The existing mock supplies real HTTP/SSE
replies through ReqLLM. There is no TRM executor or request process.

```elixir
ai :assistant do
  models do
    model(:answer, "openai:gpt-4o-mini")
  end

  reasoning :trm do
    model(:answer)
    options(max_supervision_steps: 5, act_threshold: 0.9)
  end

  controls do
    max_iterations(15)
    max_model_calls(15)
  end

  requests do
    mode(:session)
    streaming(true)
  end

  result(nil, into: :reply)
end
```

Declare the domain field and route as shown in the example. DSL, source data,
Builder and registered source JSON produce the same definition. Direct Flow
execution and ordinary Agent turns use the same method. The public `TRMAgent`
macro and retained namespace/Strategy helpers are now covered by [09_09](../09_09_trm_api/README.md).

## Method and result rules

`max_supervision_steps` defaults to 5 and must be a positive integer.
`act_threshold` defaults to 0.9 and must be a number from 0 to 1. Unknown keys
are rejected. The common iteration, model-call and time budgets also apply.
Each full cycle needs three model calls. The example declares 15 calls and
iterations so it can complete all five cycles. A lower common budget can stop
the method between phases without a domain result commit.

The first reasoning response becomes the initial answer. Each supervision
response scores the current answer, using the retained `SCORE:` parser and
feedback rules. Each improvement replaces the current answer and enters the
answer history. Later reasoning supplies analysis; it does not replace that
current answer before the next review.

The final result is the latest completed improvement. It can be newer than the
highest reviewed answer. `best_answer` and `best_score` separately retain the
highest scored answer, with the earlier answer winning ties. When all scores
are zero, `best_answer` remains empty while the current improvement is returned.
The tests expose both values and do not claim that the final improvement was
reviewed.

Stopping is checked after improvement. The step limit takes precedence over
ACT in the same cycle. ACT stops at the threshold or when the last three scores
have a range below 0.02. It also retains the existing near-maximum quality stop
at 0.98, even if the declared threshold is higher. That last stop maps to the
legacy `:act_threshold` termination value. Tests preserve this naming limit.

Successful output remains a string. Completed metadata stores method data at
`meta.reasoning.trm`: current and best answers, scores, feedback, ACT state,
step count, answer history, usage and termination. The latent trace retains
the last 10 entries, each with at most 200 characters of model text. It is a
compact trace, not a full response transcript. The common request metadata
retains the actual model-call count and usage without duplicate accounting.

Phase prompts use the existing Reasoning and Supervision helpers. Optional
profile instructions precede each required phase prompt. This is an explicit
native authoring rule; the old Strategy did not offer a custom prompt setting.
Model options default to 1024 tokens and temperature 0.2. Explicit options
override them. The examples verify streaming and non-streaming requests.

## Failure and observation

Failures retain `{:failed, cause, details}` with the original canonical cause,
method state, phase and usage. The retained Machine still returns its printable
legacy error, such as `"Error: provider_down"`. The native path keeps that text
separate from the cause. Output rejection retains the selected answer in method
data while the domain result remains unchanged. A later request starts fresh
and leaves previous request records intact.

Each phase has a distinct model-call ID and Machine phase-call ID. Model
completion events carry `:reasoning`, `:supervision` or `:improvement` plus the
supervision step. The outer request ID stays fixed. Signals and telemetry use
the common event path; native requests suppress duplicate Machine telemetry.
Direct Machine callers retain the existing lifecycle and step events.

The tests fail each phase with an empty length-limited provider response. They
also cover cancellation during supervision and improvement, a deadline during
supervision, owner loss during improvement, transport cleanup, busy rejection
and a later request. These cases prove current interruption, not durable phase
resumption. Rejected admission still has the shared method-identity gap listed
in [09_07](../09_07_got_api/README.md).

The [Machine](../../../lib/jido_ai/shared/trm_machine.ex),
[ACT](../../../lib/jido_ai/shared/trm_act.ex),
[Reasoning](../../../lib/jido_ai/shared/trm_reasoning.ex),
[Supervision](../../../lib/jido_ai/shared/trm_supervision.ex) and
[Helpers](../../../lib/jido_ai/shared/trm_helpers.ex) retain their module names.
Finite transitions replace Fsmx. Usage uses the shared nested merge and adds
missing totals when both token counters are present. All 204 retained tests
for these five modules pass on v3 dependencies. The added Machine cases check
stale and repeated phase results, terminal replay, map round trips and usage.
The old text filters remain compatibility behavior; they are not a security
boundary or a general secret-removal mechanism.

## Remaining gates

Full public/API parity, old command/phase-input mapping, runtime model and
state overrides, CLI and capability APIs, complete provider/media contracts,
active inspection, state conversion and durable recovery remain required.
Typed results, rich queries, tools and steering are rejected in this native
slice. A request transformer cannot enable tools. Those explicit limits do not
close the broader feature/API requirements. The root package still uses v2
dependencies and has not passed the v3 package or consumer gates.
