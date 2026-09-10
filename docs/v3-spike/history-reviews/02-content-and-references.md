# History review 02: content, file references and stored messages

Reviewed on 2026-09-06 against `fc5bc1434ddb69493fe8a68443f03bc6a198c5a2`.
This pass completes source review for nine more commits, bringing the total to
21 of 126. All v3 port checks remain pending. No production code changed and
no tests ran during this pass.

The review read complete commit diffs, messages, tests, PR discussions and
linked user reports. Relevant behavior was traced to the target revision.
The generated-media PR was read for follow-up requirements during this pass.
Its complete source review is now recorded in
[review 03](03-media-and-errors.md). See the
[structured ledger](../history-audit.json).

## Commit dispositions

| Commit | Final requirement to retain | Required example variants |
| --- | --- | --- |
| `e722df60` / PR 211 | Request `extra_refs` reach the user entry. Application refs cannot replace the reserved atom-keyed IDs on that entry. | HIST-03: external refs, reserved refs |
| `b77f3374` / PR 209 | Tool content parts remain content parts beside structured output. Context import and restore preserve them. | HIST-03: image tool result, representation parity |
| `977c710d` / PR 213 | Refs survive context entries, message projection, replay, restore and runtime assistant/tool events. | HIST-03: projected refs, restored refs |
| `e5c8035c` / PR 250 | File parts and raw image bytes stay outside the tool result's JSON text. All content parts still reach the provider content path. | HIST-03: binary tool results |
| `3a933a46` / PR 278 | ReAct accepts content-part queries through Agent helpers, direct calls and Actions. Event summaries must not replace full input. | HIST-03: multimodal query, entry-point parity |
| `4833c863` / PR 298 | Request file options append normalized content parts. Request handles and tracked queries retain the complete input. | HIST-03: file options, invalid references, request tracking |
| `b25b38b8` / PR 304 | A valid content-part query starts actual delegated work and reaches ReqLLM. | HIST-03: live file request |
| `f9faad7d` / PR 306 | Context and tool import preserve uploaded file IDs, MIME types, filenames and document metadata. | HIST-03: MIME and metadata, provider encoding, restored files |
| `c12600ea` / PR 329 | Assistant text and thinking survive JSON string keys. Invalid thinking values cannot hide valid text fallbacks. | HIST-04: JSON restore, malformed thinking |

## One example can expose several distinct failures

Use a document-review Agent in catalog 03 and 06. It receives a document
reference and an external message ID. The model requests a real document tool.
The tool returns structured findings and a small binary attachment. A second
model request must contain that tool result. Store the completed conversation,
restore it, then ask a follow-up question.

Keep each failure as a separately named test variant. A successful final answer
alone is insufficient: the mock could answer even when the document was lost.
Each script must match the required content in the actual request. Also inspect
the committed history and the application context before provider encoding.

| Boundary | Required observation |
| --- | --- |
| Request admission | Original content order, normalized file references and external refs are present. Invalid setup starts no model/tool work. |
| Runtime start | A valid list query causes an HTTP request. An accepted handle alone does not prove execution. |
| Tool completion | The real Action result supplies the structured output and bytes. The mock does not supply the tool result. |
| Next model call | Correct tool-call ID, output envelope, separate media blocks and file MIME type reach the actual provider encoder. |
| Commit | Full supported content, tool-call/result pairs and application refs remain available. Unrelated Agent state remains intact. |
| Restore and next request | Import does not erase text, thinking, media or refs. The later request uses the restored content. |

For a model failure after the tool runs, retain the plan's prior-state rule and
record that completed external tool work cannot be undone. For invalid file
options, fail before dispatch and preserve the prior state. These are different
failure boundaries and require separate assertions.

## HIST-03: content parts are not tool JSON

[Issue 208](https://github.com/agentjido/jido_ai/issues/208) asks for structured
data plus an image that the model can see. Encoding the image as ordinary JSON
text did not satisfy that use case. [PR 209](https://github.com/agentjido/jido_ai/pull/209)
keeps the parts beside a text representation of the structured output.

The author's PR comment proposed a broader alternative across three repositories.
The discussion accepted the smaller approach as useful. Those unmerged proposal
links do not establish extra released APIs for v3 to preserve.

Later PR 230 introduces the canonical success/error envelope, and PR 250 keeps
binary parts out of its JSON payload. Use the final target behavior, not the
earliest PR 209 test's bare JSON shape. For example, the target encodes a tool
map with `summary: "checked"` and a PDF part as:

```text
tool content[0]: JSON text {"ok": true, "result": {"summary": "checked"}}
tool content[1]: file content part with the original bytes and application/pdf
```

The content part is subsequently encoded using the provider's format. JSON text
must contain no raw PDF bytes and no `__content_parts__` carrier key. The full
HTTP body can contain the provider's base64 representation of those bytes.

The [PR 250 report](https://github.com/agentjido/jido_ai/pull/250) showed a real
`Jason.EncodeError` from non-UTF-8 PDF bytes. Cover all three accepted tool
representations: a map with `__content_parts__`, `ReqLLM.ToolResult`, and a bare
content-part list. Include atom and string map keys. A file-only list has a
success envelope with a null result plus the separate file part.

Also cover structured output plus an image URL, raw image bytes, text-only
output, and ToolResult metadata. The target may include safe content summaries
inside the JSON result as well as separate parts. Do not remove this accepted
shape during simplification without a recorded compatibility decision.

The current filter excludes every `:file` part, including uploaded file IDs,
and image parts with binary data. It does not implement a general proof that
every metadata value is JSON-safe. Transport sanitization has later audit rows;
do not claim this one fix covers every arbitrary binary value.

Baseline evidence: [tool result formatting](../../../lib/jido_ai/turn.ex),
[Context](../../../lib/jido_ai/context.ex),
[tool result tests](../../../test/jido_ai/turn_test.exs),
[executor tests](../../../test/jido_ai/executor_test.exs), and
[context tests](../../../test/jido_ai/thread_test.exs).

## HIST-03: external refs survive projection and restore

[PR 211](https://github.com/agentjido/jido_ai/pull/211) adds request `extra_refs`
for identifiers such as a Slack timestamp or external message ID. PR 213 then
extends the data path through Context and runtime events. Keeping refs only
in the original stored entry is insufficient.

Use synthetic values such as `external_message_id: "message-42"`. Assert them
after request construction, context projection, history commit and restore.
Cover user, assistant, tool and system entries where the Context API supports
them. Mixed histories must retain missing refs as missing. Imported empty or
invalid refs normalize to no refs. Compare both message import and raw Context
map import; they are separate supported paths.

For runtime assistant and tool entries, preserve request/run correlation and
the source event ID. Test two tool calls so that a copied ID cannot pass by
accident. The old Thread layout is evidence of behavior, not the v3 storage API.
Core owns the new state commit; AI owns the conversation data and projection.

The old protection has a limit: it removes reserved atom keys when building
Thread entries. Initial run-context refs receive the supplied map directly.
It does not establish uniform protection for string keys after JSON conversion.
For v3, define one reserved-ID rule across live and restored data and test both
key forms. Treat this as a normalization decision, not proof of uniform v2 behavior.

Refs are application metadata. The selected ReqLLM Message schema has no `refs`
field. A provider need not receive arbitrary application refs on the wire.
Inspect the AI context or request-transformer input for those refs, and inspect
HTTP for the supported provider content. Do not move refs into prompt text just
to make a wire assertion pass.

Baseline evidence: [Request](../../../lib/jido_ai/request.ex),
[ReAct projection and event refs](../../../lib/jido_ai/reasoning/react/strategy.ex),
[Context refs tests](../../../test/jido_ai/context_refs_test.exs),
[request tests](../../../test/jido_ai/request_test.exs), and
[ReAct tests](../../../test/jido_ai/strategy/react_test.exs).

## HIST-03: file requests reach the provider with their MIME type

[PR 278](https://github.com/agentjido/jido_ai/pull/278) adds content-part queries.
[Issue 292](https://github.com/agentjido/jido_ai/issues/292) asks for convenient
uploaded file references through generated Agent helpers. PR 298 adds request
options outside `llm_opts`, so the file is part of the user message.

Preserve `file_id`, `file_ids`, `file_reference` and `file_references`. References
can be strings, maps or keyword lists. A keyword list that describes one file
must remain one reference. Cover nested `source` maps and keyword lists, trim
identifier/filename/MIME whitespace, and retain supplied metadata. Existing query
parts precede appended files. Cover multiple options together and verify order.

Missing file options leave the query unchanged. Missing IDs and malformed
reference lists return the structured invalid-file-reference error before
dispatch. An absent MIME value defaults to PDF for uploaded references; ordinary
binary files have a different default. Request handles, stored request queries
and `last_query` must not narrow a content-part list to text.

The old compatibility branch returns an explicit error when ReqLLM lacks
`ContentPart.file_id/3`. The v3 dependency set must provide the required API.
Do not retain conditional tests that can pass without testing any file support.
If an unsupported-version path remains in the supported matrix, test it separately.

The conversation in [issue 302](https://github.com/agentjido/jido_ai/issues/302)
is essential. It exposed these separate failures:

1. The delegated worker still required a binary query, despite accepting list
   queries in its schema. PR 304 fixes actual work startup.
2. The user then confirmed requests and responses worked, but `text/plain` and
   `application/pdf` became `application/octet-stream`. PR 306 fixes rehydration.
3. A related ReqLLM investigation found file-ID loss in OpenAI Responses. That
   encoder fix alone could not fix the user's Anthropic worker path.

Run a generated Agent helper through a live server with both `text/plain` and
`application/pdf`. Require the first HTTP request and terminal completion within
a bounded test deadline. Then repeat the request after context import/restore.
This detects the old silent worker no-op and the later MIME loss independently.

Context and tool import must accept `file`, `file_id` and `document` map types
with atom or string keys. Preserve the file ID, filename and MIME type from
supported top-level or nested source fields. Preserve document title, context
and citations according to the import path. Existing metadata has precedence
when that path uses `Map.put_new/3`. Query option attachment and Context import
do not read every metadata field from identical locations; record any intended
unification in the API migration table.

Query validation in the target is a nonempty-list/type-shape check. It does not
prove arbitrary part contents or impose a universal byte/count limit. Test
invalid query shapes at validated Agent/Action boundaries. Define any stronger
v3 limits with the shared input policy, and do not present them as old guarantees.

Use catalog 01–03 for shared operations, 05 for live helper parity, and 06/14
for restored or resumed input. Include `ask`, `ask_stream`, `ask_sync`, direct
ReAct, and Start/Continue/Collect Actions where supported. Preserve full input
for the model while keeping image/file summaries in the applicable event fields.

Baseline evidence: [Query](../../../lib/jido_ai/query.ex),
[generated Agent helpers](../../../lib/jido_ai/authoring/agent.ex),
[Request](../../../lib/jido_ai/request.ex),
[worker startup](https://github.com/agentjido/jido_ai/blob/fc5bc1434ddb69493fe8a68443f03bc6a198c5a2/lib/jido_ai/reasoning/react/worker/strategy.ex),
[Query tests](../../../test/jido_ai/query_test.exs),
[request tests](../../../test/jido_ai/request_test.exs),
[worker regression](https://github.com/agentjido/jido_ai/blob/fc5bc1434ddb69493fe8a68443f03bc6a198c5a2/test/jido_ai/react/worker_strategy_test.exs), and
[runner tests](../../../test/jido_ai/react/runtime_runner_test.exs).

## HIST-04: stored assistant text and thinking remain usable

[Issue 328](https://github.com/agentjido/jido_ai/issues/328) describes a JSONB
storage use case. Exported messages gain string keys after a JSON round trip.
The old assistant extractor ignored those keys and stored empty content. A
later save could then replace the original useful conversation with empty data.

Create a completed assistant message with text and synthetic thinking content.
Export it, encode and decode it with Jason, import it, then ask a follow-up.
Assert both the reconstructed Context and the next model input. Repeat with a
raw string-keyed Context map through `coerce/1`. Pure text results must retain
their existing string form.

Cover multiple text/thinking parts, mixed atom/string key forms, and malformed
thinking fields with valid text fallbacks. The final helper selects a binary
field; a truthy numeric `thinking` value must not suppress valid fallback text.
Fully malformed text/thinking parts keep the existing empty/nil result instead
of becoming fabricated content.

PR 340 later adds generated media and fixes thinking-plus-media projection.
Its review found two additional boundaries: the default policy could stringify
a content-part delta, and Context could wrap a whole content list as one text
value. Add those HIST-04 variants when that full source review is complete.
Do not mark generated-media parity proved by the JSON text/thinking case.

Baseline evidence: [Context extraction/projection](../../../lib/jido_ai/context.ex)
and [JSON/invalid-thinking regressions](../../../test/jido_ai/thread_test.exs).

## One mock server, several required provider formats

The existing Chat Completions mock cannot prove these provider-specific cases.
Extend the same server and script/report contract when implementing the ports.
Keep real ReqLLM encoding and real Actions. No external file upload is needed;
use synthetic file IDs and local fixture bytes.

| Format and source | Required local transport assertion |
| --- | --- |
| Bedrock Converse; [ReqLLM PR 516](https://github.com/agentjido/req_llm/pull/516), linked from PR 209 | A tool result contains both text and encoded image content. Use synthetic credentials and a local endpoint. The text-only encoder must fail the test. |
| Anthropic Messages; [ReqLLM PR 677](https://github.com/agentjido/req_llm/pull/677) | Uploaded file IDs become the correct document/image source; the required file header is present. Preserve the tested MIME/document metadata through the AI path. |
| OpenAI Responses; [ReqLLM issue 739](https://github.com/agentjido/req_llm/issues/739) | A file-ID-only part remains an `input_file` item in the HTTP request instead of disappearing. |

These upstream records explain transport requirements. They do not add their
commits to the 126-commit Jido AI range. The installed acceptance dependency
contains corresponding encoders, but source inspection is not a passing v3
integration test. Generated-media streaming and WebSocket cases remain separate.

At the shared-operation simplification check, compare Query, Context and tool
content normalization. Share common field handling where behavior agrees.
Retain public string/list result shapes and documented metadata precedence.
At the recovery check, rerun the same cases after JSON import and state restore.
Do not add another conversation engine or another mock to close these gaps.

## Initial-State rich append evidence: 2026-09-07

[14_08](../../../examples/14_resume/14_08_query_append/README.md) extends PR 278's
entry-point evidence. A real standalone State adds text and an uploaded file
ID; the buffered Responses request contains the earlier user entry and complete
new content once. The actual provider encoder rejects PDFs on buffered Chat
Completions, so this fixture selects the supported Responses format. This is
not evidence for all providers or for released v2 State conversion.

## Standalone old-State content conversion: 2026-09-07

[14_09](../../../examples/14_resume/14_09_state_migration/README.md) proves an old
State-format-v3 map retains uploaded PDF content and refs through explicit
conversion and buffered Responses encoding. The current system instruction and
user input each appear once. This adds one partial PR 278 reference. Other
provider/media paths remain required.


## Native context-operation evidence: 2026-09-07

[02_23](../../../examples/02_requests/02_23_context_operations/README.md) adds 28 cases
for real Agent context operations. The linked ledger references cover core
Thread request refs, pending-operation recovery, durable terminal application
and accepted-history compaction. The original skill call and result now replace
conflicting assistant/result copies. Typed ReqLLM calls are supported.
Actual LoadSkill/callback/catalog provenance and resource loading still need
the complete skill port. This evidence does not close those history rows or
the old Agent conversion and root package gates.
