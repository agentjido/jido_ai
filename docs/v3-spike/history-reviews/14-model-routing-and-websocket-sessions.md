# History review 14: model routing and WebSocket sessions

Execution update, 2026-09-07:
[02_19](../../../examples/02_requests/02_19_model_options/README.md) now covers public
request model overrides, selected-model option merging, actual SSE labels and
headers, and buffered Responses tools/objects. It reuses the existing resolver
and Config merge functions. No separate session or executor was introduced.
The mock still needs Responses streaming and WebSocket support. The full
within-loop provider-switch, continuation and ownership cases below remain
required. This is partial PR 295 evidence.

Reviewed on 2026-09-06 against `fc5bc1434ddb69493fe8a68443f03bc6a198c5a2`.
This pass completes two more source reviews. The total is 87 of 126.
All v3 port evidence remains pending.

Read both complete diffs, PRs 272 and 295, and every captured comment and review
on the superseded PR 289. Inspect the final runtime/configuration source and
the local ReqLLM transport boundary. No runtime tests were run in this pass.

| Commit / PR | Retained behavior | Acceptance mapping |
| --- | --- | --- |
| `da7cfba6` / PR 272 | Optional Responses WebSocket reuse, caller/runner ownership, cleanup and safe stream cancellation. | HIST-15: reuse, caller ownership, cleanup, fallback, session scope |
| `2f7b8d61` / PR 295 | Per-turn model overrides affect provider options, requests, Turns, public events, usage and telemetry. | HIST-01: runtime routing, option shapes; HIST-15: effective model, continuation, session scope; RELEASE: routing guide |

## Reproduce the settings-driven provider change

[PR 289](https://github.com/agentjido/jido_ai/pull/289) describes an application
that switches between Fireworks and xAI through a settings control. An option
such as `xai_api: :responses` must apply to the xAI call. The configured default
model must not decide that call's provider behavior.

The [blocking review](https://github.com/agentjido/jido_ai/pull/289#pullrequestreview-4330838668)
found that requests used the override, but response handling and WebSocket setup
still used the configured model. Later comments added delta labels and tuple
model forms to the required checks. The final
[maintainer disposition](https://github.com/agentjido/jido_ai/pull/289#issuecomment-4501363846)
identifies PR 295 as the merged result. Preserve those checks from the final
diff. The unmerged contributor branch is context, not a separate released port.

Extend catalog 13 with a report Agent. The first model call asks for a real
lookup Action. Hold that Action while the test changes the trusted model
selection. The next turn must use the selected provider, endpoint, model and
options. Capture the actual request and the resulting model labels, usage and
events. Run the same workflow with streaming enabled and disabled.

The baseline rebuilds the request from `config.model` on each turn. A transformer
override is per-call; it does not permanently replace the configured default.
An omitted or nil model override retains that turn's base model. Resolve model
aliases and rich values before merging option overrides. The final tool list
is regenerated from the selected executable tools after transformation.

| Variant | Required evidence |
| --- | --- |
| `HIST-01/runtime-routing` | Switch Fireworks to xAI and back during one tool loop. Verify actual model/endpoint/options, selected-model labels in started/delta/completed events, public results, usage and telemetry. Cover aliases, strings, model maps and accepted tuple forms. An omitted later override returns to the configured default. |
| `HIST-01/runtime-option-shapes` | Exercise old three-argument and new effective-model option merging, nil overrides, keyword/map forms and known string keys. Observe selected-provider validation at the real ReqLLM boundary. Test incompatible inherited options, malformed values and unknown keys without new atoms or HTTP work on rejection. |
| `HIST-15/effective-model` | Start with a non-OpenAI default and select OpenAI or OpenAI Codex; then test the reverse. Create or use a Responses session only for a compatible selected operation. Verify tuple provider selection, streaming/non-streaming behavior and first-turn versus later-turn changes. |
| `RELEASE/runtime-routing-guide` | Compile and run the supported transformer example with the v3 public API and trusted model fixture. Keep guide, callback input/output types and generated Agent behavior aligned. Test failures before dispatch and retain useful diagnostics. |

The helper's documentation says provider options are revalidated. The source
does less: it uses the selected provider's key map to normalize string keys,
then retains atom keys and merges options. It does not itself validate every
value against the provider schema. Existing atoms can also be accepted from
strings. The final provider boundary must establish actual validity.

The merge is shallow. An explicit `provider_options` override replaces that
whole nested option list. A nil LLM-options override returns base options
unchanged, even after a model change. String keys in maps and malformed entries
in lists also take different paths. Retain the documented input forms through
one explicit adapter; do not infer a deep merge or a strict validator from the
helper name. Reuse HIST-20 checks from the data conversion review.

The runtime emits `llm_started` after successful request preparation, with the
prepared message count and selected model label. A transformer error must not
emit a successful model-start event or perform HTTP work. This differs from
the direct Action start event, which precedes validation as review 12 records.
The Turn label uses the selected model even if a response contains another
model string. Keep requested identity and any provider-returned identity in
their defined locations rather than silently replacing one with the other.

## Prove one real session through a tool loop

[PR 272](https://github.com/agentjido/jido_ai/pull/272) adds optional reuse for
OpenAI Responses and OpenAI Codex. The runner stores a session PID in its
process dictionary and injects it into model options. A caller-supplied session
is forwarded and is not entered in the runner's owned-session slot.

The gate requires a supported provider, the reuse flag and WebSocket transport.
The runner accepts several legacy truthy flag forms, but ReqLLM's provider
schema can impose narrower types. Test the full accepted public contract.
Without reuse, the normal selected transport still applies. A missing session
helper or a returned startup error leaves options unchanged; that is not proof
of an automatic switch from WebSocket to SSE or HTTP.

Use one Responses conversation with two model turns and a real Action between
them. The mock records one upgrade and socket identity, both `response.create`
messages, tool-call IDs, the Action output and response IDs. Then run it with a
caller-created session and send another valid request on that same session
after the AI request ends. A PID merely present in options is insufficient.

| Variant | Required evidence |
| --- | --- |
| `HIST-15/reuse` | With reuse enabled, one live session serves multiple actual Responses model turns. Assert one connection, ordered frames, real tool execution/output, correct call IDs and final result. With reuse disabled, retain the selected normal transport and its documented connection behavior. |
| `HIST-15/caller-ownership` | Supply a real live session and retain its identity across the run. After success, failure and cancellation, the caller can use or close it. Reject invalid/dead handles through the defined error path without silently taking ownership. A caller handle must remain outside portable Agent state. |
| `HIST-15/cleanup` | Monitor runner-owned session and socket cleanup on success, model/tool failure, cancellation, early stream halt and owner death. Also stop a session before cleanup. Close/cancel errors cannot replace the original outcome or hang the caller. Verify cleanup after terminal delivery, since the baseline sends completion before its `after` block closes the session. |
| `HIST-15/fallback` | Cover missing helper capability, startup failure, handshake rejection, disconnect and selected transport fallback. Inspect actual attempts and errors. Do not treat unchanged options as successful fallback or retry ambiguous work without a policy. If the supported v3 ReqLLM floor always supplies the helper, document removal of the old capability check. |
| `HIST-15/continuation` | Capture real Responses bodies/frames across a tool loop. Preserve compatible response IDs and matching function-call outputs. Cover missing IDs, caller/transformer overrides, `store: false`, and the selected provider's encoding. Prove full-history behavior where continuation is unavailable. |
| `HIST-15/session-scope` | Change provider, model, endpoint or trusted credential binding after the first session exists. Reuse only a compatible session. Never send new credentials or conversation state through the wrong connection. Cover dead cached sessions, concurrent runs, a second request, and restore with fresh runtime handles. |

The baseline tests use `self()` for caller ownership and an already dead PID
for session setup. Those tests prove forwarding and provider selection. They
do not prove a handshake, live reuse, cleanup, or connection isolation.

## Session and continuation limits found in source

The runner has one PID slot with no connection identity or liveness check on
reuse. A later compatible-provider test can therefore reuse the first cached
PID without comparing provider, endpoint or credentials. The hardening in
PR 295 fixes which model selects setup; it does not prove session replacement
after a later provider change. V3 needs an explicit session identity and owner.
Keep credential material in trusted runtime bindings, not in the portable key.

Likewise, state stores one response ID without provider/session provenance.
It is added to options before transformation. A nested provider-options override
can replace it, while a model-only override can retain an ID from a different
provider. Test both orders and scope continuation to its compatible owner.
The existing configuration fingerprint does not establish the validity of a
remote response ID after restore or a dynamic model change.

Provider encoders can change the final body. In the inspected local ReqLLM,
OpenAI HTTP with `store: false` suppresses previous-response chaining, while
WebSocket encoding can retain it. The Codex tool-resume path can remove that
field. The AI option alone is not wire evidence. Assert the actual supported
encoding and full transcript, not universal presence of one option.

The original commit also changes stream-cancel handling to catch exits/throws
as well as exceptions. Keep that behavior with the dead-stream cleanup cases
from review 07. A cleanup callback must not turn a completed request into a
failure when its provider process already stopped.

## Mock and simplification requirements

Extend the existing mock server with Responses HTTP/SSE and WebSocket support
when this port starts. Use the same per-test script, barriers and diagnostics.
Record upgrade headers, connection IDs, request frames, server frames and close
events. Include fragmented tool arguments, terminal/error frames and disconnects.
Use the real ReqLLM client and decoder, including local synthetic Codex auth
bindings where required. The inspected URL builder supports a local `ws` URL.

Do not replace the transport with a prebuilt Turn, scripted runtime response,
or fake session PID in these integration cases. Keep focused helper tests for
pure option normalization. The existing Chat Completions mock is a foundation;
it cannot yet establish WebSocket or Responses parity.

At authoring/shared operations, retain one model resolver and one prepared-call
record. At live requests, put session ownership, continuation identity and
cleanup in the same runtime owner. At repair/recovery, re-evaluate current model
and credentials through the existing preparation path. Reuse the repair checks
from review 04; do not add another request transformer or session scheduler.

Source: [runner](https://github.com/agentjido/jido_ai/blob/fc5bc1434ddb69493fe8a68443f03bc6a198c5a2/lib/jido_ai/reasoning/react/runner.ex),
[configuration](../../../lib/jido_ai/reasoning/react/config.ex),
[transformer](../../../lib/jido_ai/reasoning/react/request_transformer.ex),
[projection](../../../lib/jido_ai/reasoning/react/strategy.ex),
[state](../../../lib/jido_ai/reasoning/react/state.ex),
[Turn](../../../lib/jido_ai/turn.ex), and
[model helpers](https://github.com/agentjido/jido_ai/blob/fc5bc1434ddb69493fe8a68443f03bc6a198c5a2/lib/jido_ai.ex).

Tests: [runtime runner](../../../test/jido_ai/react/runtime_runner_test.exs),
[effective-model configuration](../../../test/jido_ai/reasoning/react/config_runtime_model_test.exs), and
[ReAct projection](../../../test/jido_ai/strategy/react_test.exs).
Guide: [standalone runtime](../../../guides/user/standalone_react_runtime.md).
