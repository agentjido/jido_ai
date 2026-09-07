# History review 03: generated media, errors and completed results

Reviewed on 2026-09-06 against `fc5bc1434ddb69493fe8a68443f03bc6a198c5a2`.
This pass completes ten more source reviews. The total is 31 of 126.
All v3 port checks remain pending. This pass changes documents only.
No tests ran during this pass.

The review read the complete commit diffs, tests, documentation, associated
PR discussions and relevant user reports. Follow-up changes were traced to
the target revision. See the [structured ledger](../history-audit.json).

## Commit dispositions

| Commit | Final requirement to retain | Required variants |
| --- | --- | --- |
| `0161b30e` / PR 340 | Ordered generated content survives Turn, live events, policy, ReAct/CoT results and conversation replay. Text-only results stay strings. | HIST-04: media stream, image-only answer, mixed replay, capture modes, method scope |
| `68fda90a` / PR 214 | Instruction failures retain their cause in error details. Use the correct constructor for each package. | HIST-14: instruction details |
| `6ecc5c32` / PR 230 | Tool messages contain a canonical success/error envelope. Local result tuples, correlation and conservative retry decisions remain available. | HIST-14: canonical tool result, tool failure, retry contract; HIST-03: binary tool results |
| `9f35a897` / PR 223 | ReAct, CoT and CoD retain raw failure terms for callers. Legacy text fields and CLI output remain printable. | HIST-14: raw failure, compatibility text |
| `4ef91e0e` / PR 233 | Completed request records retain available usage and reasoning metadata. `ask_sync` and `await` keep their result shape. | HIST-14: completed metadata, metadata precedence |
| `95ec8d19` / PR 234 | Adaptive retains raw request errors and string-valued legacy/CLI output. | HIST-14: raw failure, compatibility text |
| `e0bdade3` / PR 258 | Action error structs cannot become broken struct-shaped maps during tool JSON encoding. Validation failures keep their validation type. | HIST-14: tool failure, instruction details |
| `5b7332f1` / PR 275 | Error details containing tuples, process IDs, references and nested terms have an encodable representation. | HIST-14: error details |
| `d1fb1fbe` / PR 296 | Completed ReAct tool outputs have their own inspection surface. Preserve IDs, arguments and normalized results, without replacing the final answer. | HIST-14: completed tools |
| `d60699c0` / PR 299 | `Jido.AI.Error` owns error normalization, serialization, result normalization and retry rules. Decoded envelopes keep known types and retry hints. | HIST-14: runtime errors, JSON restore, retry contract |

## HIST-04: generated images must pass through the whole path

[Issue 336](https://github.com/agentjido/jido_ai/issues/336) identifies several
separate losses after the provider decoder. Adding a field to ReqLLM alone did
not fix Turn construction, live events, text accumulators or stored messages.
[PR 340](https://github.com/agentjido/jido_ai/pull/340) fixes these paths.

The source keeps ordered `content_parts` on Turn. `Turn.result/1` and
`Turn.assistant_content/1` return a string for text-only output. If visible
non-text parts exist, they return the ordered visible parts. Thinking remains
separate from that visible result. Adjacent text chunks can merge, but text
on opposite sides of an image must not move across the image.

Two PR review findings become named integration cases:

- [Default policy](https://github.com/agentjido/jido_ai/pull/340#discussion_r3685725692):
  a complete typed image part must survive delta sanitization. A text length
  limit must not convert the part to a string or truncate the image.
- [Conversation replay](https://github.com/agentjido/jido_ai/pull/340#discussion_r3685725696):
  thinking must combine with an existing content list as a flat list.
  Wrapping that list inside a text part makes the next request invalid.

Use one illustration Agent in catalog 05 and 06. It receives generated media,
runs a real annotation Action, then makes another model call. Keep the tests
small enough to identify which boundary lost the media.

| Variant | Input and required evidence |
| --- | --- |
| `HIST-04/media-stream` | Send adjacent text chunks, one image part, then more text. Hold the stream before its end. Observe the complete typed image event before terminal commit. Assert content order in the final result and history. Repeat with the default policy and a five-character text limit. |
| `HIST-04/image-only` | Send an empty text field and an image in the same provider delta. The result is a successful visible image, not an empty string. Also test a non-streaming response with an image and empty text. |
| `HIST-04/mixed-replay` | Send synthetic thinking, text, an image and a tool call. Execute the actual Action. Inspect the next AI message projection and provider request: content is flat, the image survives, and the tool ID/result pair is correct. Repeat after supported history export/import. |
| `HIST-04/capture-modes` | With capture enabled, media events arrive live. With capture disabled, delta events are absent but final content remains intact. A failed stream after a media event produces a failed request and no final-answer commit. A later ordinary request still works. |
| `HIST-04/method-scope` | Prove complete media results through ReAct and CoT, and through CoD where it delegates to the CoT path. For the other methods, prove that typed media does not enter a binary text accumulator. Do not claim complete generated-media results for every method from that guard alone. |

The source change gives several other reasoning machines a binary guard and
broadens their delta schemas. It does not prove that AoT, ToT, GoT, TRM and
Adaptive all return rich media as final results. Any broader support needs its
own feature decision and positive example during the method port.

At the source baseline, ReAct and CoT preserve the rich result. Legacy
`last_answer`/`last_result` fields can still be compatibility strings. Test the
canonical result separately from these display fields. The CoT media path
does not parse the part list as a textual conclusion or reasoning steps.

The existing tests often replace `ReqLLM.Generation` or stream processing.
They prove useful AI-level behavior, but they do not prove the provider decoder.
The v3 case must use the same HTTP mock and real ReqLLM transport.

The linked [ReqLLM report 933](https://github.com/agentjido/req_llm/issues/933)
supplies the concrete provider failure: OpenRouter sends images in
`choices[].delta.images` beside `content: ""`. Non-streaming images can appear
in `choices[].message.images`. Use this shape, with small synthetic data:

```json
{
  "choices": [{
    "index": 0,
    "delta": {
      "content": "",
      "images": [{
        "type": "image_url",
        "image_url": {"url": "data:image/png;base64,AAECAw=="}
      }]
    }
  }]
}
```

This payload tests transport bytes; it is not a valid rendered PNG fixture.
Use a valid small image when a test exercises image validation. The installed
ReqLLM 1.22.0 default decoder reads the image field and creates typed content
parts. Test a data URI and an image URL through that actual decoder. The
OpenRouter model must target the local mock with synthetic credentials.
The mock must not fetch the image URL. Add no second mock server.

Observe thinking at the AI projection boundary when a provider omits thinking
on replay. Provider-specific omission does not justify nesting or losing other
parts. For stored binary media, use the supported storage representation;
do not assume raw non-UTF-8 bytes can round-trip through ordinary JSON.

Baseline evidence: [Turn](../../../lib/jido_ai/shared/turn.ex),
[Context](../../../lib/jido_ai/shared/context.ex),
[ReAct runner](https://github.com/agentjido/jido_ai/blob/fc5bc1434ddb69493fe8a68443f03bc6a198c5a2/lib/jido_ai/reasoning/react/runner.ex),
[CoT worker](https://github.com/agentjido/jido_ai/blob/fc5bc1434ddb69493fe8a68443f03bc6a198c5a2/lib/jido_ai/reasoning/chain_of_thought/worker/strategy.ex),
[policy](../../../lib/jido_ai/authoring/plugins/policy.ex),
[Turn tests](../../../test/jido_ai/turn_test.exs),
[runtime tests](../../../test/jido_ai/react/runtime_runner_test.exs),
[policy tests](../../../test/jido_ai/plugins/policy_test.exs), and
[context tests](../../../test/jido_ai/thread_test.exs).

## HIST-14: errors keep their meaning at each boundary

[Issue 249](https://github.com/agentjido/jido_ai/issues/249) reports a tool error
that crashes the Agent during JSON encoding. A second user reproduced it with
an input-validation error. The linked
[Jido Action report 157](https://github.com/agentjido/jido_action/issues/157)
shows the crash even after an Action error encoder patch. A directory-listing
tool returned an expected failure, but AI normalization retained struct markers
after removing required struct fields. An upstream encoder alone was not enough.

Use a directory-inspection Agent in catalog 03 and 04. A real Action reads a
test-owned temporary directory. A missing child path produces a structured
Action error. The next model request must contain a valid error envelope and
the Agent must complete its response. Repeat with missing required input,
so validation fails before the Action runs. Neither variant may crash the Agent.

Keep the following distinctions during the port:

| Boundary | Required contract |
| --- | --- |
| Core Action/Flow failure | Preserve the source error and its details through the supported v3 core error API. A constructor change must not silently discard the cause. |
| AI tool result | Normalize to `{:ok, value, effects}` or `{:error, error, effects}`. Preserve allowed effects as data until their documented owner handles them. |
| Tool message for the model | Encode `{"ok": true, "result": ...}` or `{"ok": false, "error": ...}`. The error contains type, message, details and retryability. Separate binary content parts follow the content plan. |
| Request failure | Keep the structured term presented by the runtime. ReAct/CoT/CoD/Adaptive consumers can pattern-match on it. Do not apply display conversion to the canonical error. |
| CLI and legacy text field | Preserve printable strings. Convert non-binary values at this boundary. Keep nil and ordinary text behavior. |
| Storage and restore | Store portable data, rebuild live resources and retain known error types/retry hints. Raw request error preservation does not make process IDs or arbitrary terms portable. |

The PR 214 source also shows why constructor names are insufficient evidence:
`Jido.Error.execution_error` used keyword options, while the weather example
used `Jido.Action.Error` with a map. Its example diff was formatting only.
Test the error details at the boundary; do not copy one call shape everywhere.

Required variants:

| Variant | Test and failure check |
| --- | --- |
| `HIST-14/instruction-details` | A failing real instruction retains a non-empty cause. Invalid weather input retains its type and original value without an external call. Test the supported v3 core and Action error adapters. |
| `HIST-14/canonical-tool-result` | A real tool returns text, a number, a map and a content-part result in separate cases. Inspect the next model request for the canonical envelope. Test two- and three-element result tuples. An invalid result shape becomes an explicit error. |
| `HIST-14/tool-failure` | Test missing directory, missing required input, unknown tool and a plain exception. Assert the correct type and tool/call correlation. The JSON has no broken struct markers. Invalid input and unknown tools start no Action. A tool error can reach a follow-up model call without crashing the Agent. |
| `HIST-14/raw-failure` | Cause a provider error, cancellation and worker failure through their real boundaries. Assert structured request errors for ReAct/CoT/CoD and Adaptive. Keep an HTTP failure distinct from a tool error that the model can handle. No failed request may become an empty successful answer. |
| `HIST-14/compatibility-text` | For the same failed requests, inspect CLI output and legacy text fields. They are strings while the canonical error stays structured. Include nil, ordinary text and a non-text successful result. |
| `HIST-14/error-details` | Test nested tuples, process IDs, references, structs, improper lists and non-string map keys. Assert the normalized details can be JSON encoded. Test direct envelope construction and actual model-facing tool errors. |
| `HIST-14/runtime-errors` | Model, tool, validation and task-start failures use one AI adapter. Upstream Jido/Action/Signal errors retain their supported map contract. Plain exceptions keep the selected fallback type and message. |
| `HIST-14/json-restore` | Normalize encoded-and-decoded error maps, including atom keys with string type values. Known type/code values and explicit retry hints survive. Unknown names do not create atoms. Test null messages and wrapped errors against the final target behavior. |
| `HIST-14/retry-contract` | Count actual tool attempts. Retry eligible failures only within the configured limit. An explicit false flag overrides a timeout default. False-like string hints also suppress retry. Unknown execution failures and exceptions do not become retryable by default. |

Use barriers and per-test counters, not global persistent counters. A repeated
completion event must not repeat an Action. Retry eligibility is separate from
permission to repeat external work: apply the migration plan's effect policy.
Retain completed external work when describing a later request failure; a
failed final commit cannot undo that work.

[PR 299](https://github.com/agentjido/jido_ai/pull/299) and
[issue 264](https://github.com/agentjido/jido_ai/issues/264) establish one package
owner, `Jido.AI.Error`. Keep that owner when replacing v2 runtime machinery.
The old Signal helper APIs are deprecated delegates. Preserve or explicitly
migrate those entry points; do not re-create an independent error policy there.

The current JSON safety code has a limit: binary keys, messages and values pass
through unchanged. It is not a proof that every invalid UTF-8 binary encodes.
Add a boundary decision for malformed binary error details before closing the
serialization gate. Choose a documented representation or a controlled failure;
an Agent process crash is not an accepted v3 result. This is a discovered gap,
not a claim that PR 275 already solved every binary case.

The later runtime maintenance commit `e2b2d275` changes error clause order:
wrapped errors are handled before generic `{type, message}` tuples, and nil
messages receive the fallback text. Use that final behavior. The maintenance
commit still needs its own complete source review across its other files.

Baseline evidence: [Error](../../../lib/jido_ai/shared/error.ex),
[Turn](../../../lib/jido_ai/shared/turn.ex),
[instruction helpers](../../../lib/jido_ai/reasoning/helpers.ex),
[Request](../../../lib/jido_ai/shared/request.ex),
[error tests](../../../test/jido_ai/error/model_test.exs),
[tool execution tests](../../../test/jido_ai/executor_test.exs),
[raw failure tests](../../../test/jido_ai/integration/raw_error_propagation_test.exs),
[Adaptive tests](../../../test/jido_ai/adaptive_agent_test.exs), and
[CLI adapter tests](../../../test/jido_ai/cli/adapters/adaptive_test.exs).

## HIST-14: completed metadata and tool outputs stay separate from the answer

[Issue 228](https://github.com/agentjido/jido_ai/issues/228) describes a reasoning
request whose public metadata appears empty although usage shows reasoning
tokens. A commenter proposed a richer return from `ask_sync`.
[PR 233](https://github.com/agentjido/jido_ai/pull/233) explicitly keeps the
existing return shape and enriches the stored request record. Preserve that
accepted boundary. Do not change tuple arity depending on metadata presence.

Use the same Agent for two requests: one with usage and synthetic reasoning
metadata, then one without optional reasoning fields. Inspect each completed
request by its own ID. The second request must not inherit the first request's
optional metadata. Use synthetic thinking in tests; the mock supplies it.

| Variant | Required evidence |
| --- | --- |
| `HIST-14/completed-metadata` | Available usage, reasoning details, thinking trace and last thinking reach the completed request. Empty or invalid optional values are omitted. Direct result/`ask_sync`/`await` shapes remain stable. Run through each method's supported completion path. |
| `HIST-14/metadata-precedence` | Cover atom and string keys, snapshot details, result-map fallback, the latest assistant with reasoning details, and explicit metadata overrides. Preserve unrelated request metadata. Test absent fields separately from explicit empty values. |
| `HIST-14/completed-tools` | Two real tools return distinct IDs, arguments and normalized success/error results. After the final answer, both results are inspectable without parsing prompt JSON. Replay a completion event and assert no duplicate entry or execution. Start a new run and confirm old outputs do not appear as its current results. |

Do not flatten all metadata sources into one unconditional merge. At the target,
usage falls back to a result-map value when its detail key is absent; an explicit
empty detail map suppresses that fallback. Reasoning details can fall back to
the latest assistant with non-empty reasoning data. Explicit request metadata
overrides derived metadata. The later structured-output feature adds `meta.output`.
Its full review is now recorded in [review 04](04-output-and-controls.md).

[PR 296](https://github.com/agentjido/jido_ai/pull/296) separates completed tool
outputs from pending calls. It updates existing entries by tool-call ID and
accepts string-keyed pending-call maps. Preserve those cases at the v3 public
inspection surface. This field describes the current or most recent ReAct run;
it is not the durable business record. Domain data needs its normal persistence
or an allowed state update. Final assistant content stays the canonical answer.

Baseline evidence: [Request](../../../lib/jido_ai/shared/request.ex),
[ReAct inspection](../../../lib/jido_ai/reasoning/react/strategy.ex),
[request tests](../../../test/jido_ai/request_test.exs),
[Agent tests](../../../test/jido_ai/agent_test.exs), and
[completed tool tests](../../../test/jido_ai/strategy/react_test.exs).

## Resolve conflicting PR descriptions from the actual source

PR 275 says it supersedes [PR 266](https://github.com/agentjido/jido_ai/pull/266).
PR 266's current title/body describe log probabilities, and an earlier comment
discusses stale values and a required ReqLLM decoder release. Its current file
diff instead contains the error-detail sanitation patch. Its closing comment
points to PR 275, whose merged source contains that patch.

Record both facts. Retain the merged error behavior. Do not count log-probability
support as a released feature from this reference: no corresponding API was
found in the target's `lib`, `test` or `guides` source. Keep the earlier feedback
as an optional future example: a metadata-rich request followed by one without
that metadata must not leak values, and the real provider decoder must supply
the field. The generic isolation check is already required above.

## Refinement and simplification checks

After shared operations, check that one Turn/content model and one AI error
adapter serve direct Actions and Agent calls. Keep model-facing JSON, native
results and display strings as explicit boundary conversions.

After live requests, rerun the media-policy, partial-failure, retry-count and
next-request cases. Core owns execution and commit; AI owns result meaning and
its request contract. Do not restore v2 Strategy or DirectiveExec state layouts.

After method and recovery ports, rerun result-shape, optional-metadata isolation,
tool-result deduplication and supported media restore cases. At the package
gate, test the CLI and any compatibility delegates in a fresh consumer. These
checks close only when production v3 code and the required enabled tests pass.

## Public Adaptive follow-up: 2026-09-07

The [09_11 cases](../../../examples/v3/profiles/09_11_adaptive_api.md) now give
partial PR 234 evidence. An actual HTTP 503 stays structured in the request
record and is printable in last_result. Selected-method failures retain the
actual cause and method data. Typed success and AoT/ToT maps stay canonical in
request records while the compatibility field stays a string. Pending requests
clear that field, and a later request can choose a different method. CLI-safe
output still requires its separate port. All history statuses remain pending.


## Native request inspection evidence: 2026-09-07

[02_22](../../../examples/v3/profiles/02_22_request_inspection.md) adds 14 real
integration cases. The linked history rows gain partial evidence for raw
failure inspection, per-call thinking, completed tool results, correlated
trace prefixes and portable recovery. A durable lost completion reply retains
the saved answer and prefix. A cancellation race preserves live stream order.
The stored prefix and committed outcome are distinct; this is not a complete
durable journal or delivery receipt. Old Agent conversion and the remaining
CLI, context/skill, package and recovery gates stay open.
