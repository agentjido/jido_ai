# 09_01 — CoT and CoD through the shared Flow

[Agent examples](../lib/examples/09_reasoning/09_01_linear/agent.ex) ·
[Integration tests](../test/examples/09_reasoning/09_01_linear_test.exs)

Use `reasoning :chain_of_thought` or `reasoning :chain_of_draft` in the existing
AI block. Both use the same profile validation, lowerer, model operation and
core Flow as ReAct. No new executor or request owner is added.

```elixir
defmodule Solver do
  use Jido.Agent, name: "solver", extensions: [Jido.AI.DSL]

  agent do
    schema Zoi.object(%{reply: Zoi.any() |> Zoi.default(nil)})

    ai :assistant do
      models do
        model(:answer, "openai:gpt-4o-mini")
      end

      reasoning :chain_of_draft do
        model(:answer)
      end

      requests do
        mode(:session)
        streaming(true)
      end

      result(nil, into: :reply)
    end
  end

  routes do
    route "ai.ask", ai(:assistant)
  end
end
```

The executable fixtures use the shared local mock model. Run the cases with:

```sh
mix test --include integration --seed 0 test/examples/09_reasoning/09_01_linear_test.exs
```

## Method rules

Each method makes one model call for an ordinary answer. A declared structured
output contract can add bounded repair calls. Model and request limits still
apply. Linear methods reject declared tools, request tool injection and
steering. An unsolicited provider tool call fails without tool execution or a
second model call.

Omitted or empty native instructions select the method prompt. Public Agent
prompt attributes retain missing, nil, false, empty and explicit-text behavior.
Invalid prompt values fail during authoring. Direct v2 Strategy callers now use
the AI profile or option adapter. Empty values select the CoD prompt there.

For plain text, the final answer is the parsed conclusion when one exists.
Otherwise it is the complete text. Request metadata keeps the raw text,
numbered steps, step count, conclusion, method and successful termination.
Output controls see the selected answer. Typed object output keeps its
validated value, including string fields that contain conclusion markers.
Ordered rich content remains a list. It is not reduced to the text conclusion.

The shared parser retains numbered steps, bullets, conclusion markers and the
first `####` separator. Byte-safe slices fix Unicode and adjacent markers.
Indented conclusion markers are removed correctly. Word boundaries prevent
words such as `Something` and `Answerable` from becoming conclusion markers.
The Unicode bullet `•` is recognized.

## Public API mapping

`use Jido.AI.CoTAgent` retains `think`, `think_sync` and `await`.
`use Jido.AI.CoDAgent` retains `draft`, `draft_sync` and `await`.
They are thin wrappers over `Jido.AI.Agent`. Query and cancel Signal types keep
`ai.cot.*` and `ai.cod.*`. `strategy_opts/0` retains model/prompt inspection;
execution reads the normalized AI profile. No implicit earlier-request history
is added to either wrapper. `last_prompt` and printable `last_result` remain.
Canonical request results keep rich terms and structured failures.

CoT/CoD leave `max_tokens` to the provider unless supplied. Explicit generation
options keep common precedence; `llm_opts` can override `max_tokens` and
`llm_timeout_ms`'s transport mapping. `llm_timeout_ms` maps to provider
`receive_timeout`. `request_timeout_ms` sets a separate total request budget,
with a **new 60,000 ms default**. Set a larger budget for long work. Native
profiles use `controls.timeout` and model generation `receive_timeout`.
All explicit timeouts must be positive integers. Actual transport and total
request timeouts close held provider connections.

The canonical request record and events store the method. Typed Signals and
telemetry use `:cot` and `:cod`; CoD no longer reports CoT's label. Ordinary
Agent output telemetry has the same identity. Old event maps without a method
retain the ReAct fallback. Known structured error types survive telemetry.
Cancellation keeps the caller's reason and closes work. A busy request is
refused. Restart interrupts the old request, retains its method and permits a
fresh run. Recovery retries core's exact session-owner `:restarting` refusal
within the existing five-second pre-admission limit; it never replays committed
work.

## Evidence and limits

The cases cover DSL/data/Builder/source-JSON execution, direct Flow and
ordinary Agent calls, prompts, public helpers, parsing, structured repair,
real provider errors, output rejection, method events, typed Signal delivery,
telemetry flags, budgets, cancellation, busy admission and owner recovery.
They use real ReqLLM HTTP/SSE decoding. Non-streamed rich responses include
text/image/text and image-only results; media queries reach the provider.

Two added cases stream complete image bytes through the public CoT and CoD
helpers. Canonical events and typed Signals preserve the content part and its
request, run, call, and sequence IDs before completion. The request trace and
final result retain the same bytes. The shared model callback now forwards
content parts; text inspection no longer tries to join non-text values.

The [root test transfer](../../../docs/v3-spike/linear-test-transfer.md) maps all
52 old CoT/CoD cases to native behavior checks. These cases do not prove every
provider dialect, CLI adapter, capability Plugin or v2 state conversion. The later
[09_02 example](09_02_method_api.md) adds method selection and result getters,
compiles the retained Machine and replaces the old Strategy modules with
loadable result adapters. That profile gives the callback and direct-prompt
migration rules. Pure namespace prompt, parser and call-ID helpers run on v3.
Root package and runtime-floor checks remain open.
