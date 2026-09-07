# CoT and CoD root test transfer

The four root files keep all 52 behavior cases. They now use native Agent,
Action, Flow and Session APIs. The test helper starts a local Jido instance and
uses `Jido.AI.Test.MockLLM`. It does not implement another model mock or runtime.
All four files run in the default root suite. No new skip or exclusion was added.

The source baseline is `fc5bc1434ddb69493fe8a68443f03bc6a198c5a2`.
The table gives one replacement for each old case. Names below omit their
ExUnit `describe` prefix. The case count is unchanged: 25 CoT Strategy cases,
6 CoD Strategy cases, 13 CoT wrapper cases, and 8 CoD wrapper cases.

## Contract changes

- Method selection now belongs to the AI profile. `strategy/0`, `init/2`,
  `cmd/3`, private worker routes, and Strategy action specs are removed.
  The start Action validates the query and request ID. The profile route binds
  the request to one shared session. Observation Signals cannot start model work.
- Core owns the worker. Tests hold an actual HTTP request to check admission,
  prompt delivery, worker presence, cancellation, and process cleanup. A killed
  worker produces `:worker_crash`. A later request can use the released slot.
- Busy admission returns `{:error, :busy}`. With `stream_to`, a terminal event
  identifies the rejected request. It does not insert a rejected record into
  active state or emit the old `EmitRequestError` Directive. The accepted request
  remains pending and completes once. This is an intentional v3 API change.
- Request records keep complete results and portable provider errors. Public
  `last_result` remains a printable field for CoT and CoD. The wrapper tests
  check the real streaming provider error and its HTTP cause. Non-stream tests
  check the normalized error envelope, status, and message.
- Nested usage preserves the exact old two-map merge assertion. The same case
  also runs a two-call output repair through HTTP and checks total usage. The
  arbitrary nested metadata is tested at the shared usage boundary; it is not
  claimed as a field of the OpenAI wire format.
- The trace cap test feeds events to the live Session event boundary while the
  real provider is held. It checks the first 2,000 events, overflow, and retained
  completion. It does not recreate old Strategy state.
- The image test exposed a real port defect. Complete provider content parts
  were absent from the caller stream. `Operations.Generate` now forwards them.
  Session inspection keeps them in the trace and only joins binary text.
  The root test and two integration examples check actual SSE image bytes,
  both event formats, request/call/sequence IDs, and the committed rich result.

The transfer also follows the [media and error source review](history-reviews/03-media-and-errors.md):
PR 340 requires complete generated content in live events; PR 223 requires raw
failure terms with printable compatibility fields; PR 233 requires usage in
completed request metadata. The new image cases cover a subset of HIST-04.
Replay, capture-policy variants and other method checks remain separate gates.

## Case map

### `test/jido_ai/strategy/chain_of_thought_test.exs`

| Old case | Native replacement |
| --- | --- |
| initializes delegated CoT state | [initializes an idle Agent with no request worker](../../test/jido_ai/strategy/chain_of_thought_test.exs) |
| uses default model when not specified | [uses the default model when not specified](../../test/jido_ai/strategy/chain_of_thought_test.exs) |
| resolves model aliases | [resolves a model alias before the provider request](../../test/jido_ai/strategy/chain_of_thought_test.exs) |
| uses default system prompt when not provided | [uses the default prompt when not provided](../../test/jido_ai/strategy/chain_of_thought_test.exs) |
| uses default system prompt when false is provided | [uses the default prompt when false](../../test/jido_ai/strategy/chain_of_thought_test.exs) |
| uses default system prompt when nil is provided | [uses the default prompt when nil](../../test/jido_ai/strategy/chain_of_thought_test.exs) |
| raises for non-binary system_prompt values | [rejects a non-text prompt during definition validation](../../test/jido_ai/strategy/chain_of_thought_test.exs) |
| returns spec for start action | [the start Action validates a query and request ID before admission](../../test/jido_ai/strategy/chain_of_thought_test.exs) |
| returns spec for legacy llm actions | [legacy model observations do not start work or change domain state](../../test/jido_ai/strategy/chain_of_thought_test.exs) |
| returns delegated worker routes | [query routes bind the CoT profile to the shared session](../../test/jido_ai/strategy/chain_of_thought_test.exs) |
| start emits SpawnAgent directive when worker is missing | [start commits the prompt and request before a worker runs](../../test/jido_ai/strategy/chain_of_thought_test.exs) |
| child started flushes deferred start event to worker pid | [the owned worker receives the prompt exactly once](../../test/jido_ai/strategy/chain_of_thought_test.exs) |
| request_completed worker event parses steps and conclusion | [completion parses steps and conclusion and stores usage](../../test/jido_ai/strategy/chain_of_thought_test.exs) |
| llm_completed worker events merge nested provider usage without crashing | [the shared usage merge keeps nested provider counters and metadata](../../test/jido_ai/strategy/chain_of_thought_test.exs) |
| propagates runtime ordering metadata to LLMDelta signals | [streamed deltas preserve request run call and sequence IDs](../../test/jido_ai/strategy/chain_of_thought_test.exs) |
| passes complete content parts and preserves a multimodal result | [complete content parts reach both streams and the stored multimodal result](../../test/jido_ai/strategy/chain_of_thought_test.exs) |
| request_failed worker event transitions to error state | [provider failure keeps the error and releases active work](../../test/jido_ai/strategy/chain_of_thought_test.exs) |
| request_cancelled worker event transitions to error state with cancellation reason | [cancellation keeps its reason and closes the provider connection](../../test/jido_ai/strategy/chain_of_thought_test.exs) |
| request_error instruction stores rejection metadata on strategy state | [rejection metadata identifies only the refused request](../../test/jido_ai/strategy/chain_of_thought_test.exs) |
| worker crash while active request marks request failed | [a worker crash fails its request and permits a later request](../../test/jido_ai/strategy/chain_of_thought_test.exs) |
| busy second request emits request error directive | [busy admission consumes no extra model call](../../test/jido_ai/strategy/chain_of_thought_test.exs) |
| stores request trace up to 2000 events then marks truncated | [the trace keeps its first 2000 events and records overflow through completion](../../test/jido_ai/strategy/chain_of_thought_test.exs) |
| get_steps/1 returns parsed steps | [get_steps/1 reads the committed model result](../../test/jido_ai/strategy/chain_of_thought_test.exs) |
| get_conclusion/1 returns conclusion | [get_conclusion/1 reads the committed model result](../../test/jido_ai/strategy/chain_of_thought_test.exs) |
| get_raw_response/1 returns raw response | [get_raw_response/1 reads the committed model result](../../test/jido_ai/strategy/chain_of_thought_test.exs) |

### `test/jido_ai/strategy/chain_of_draft_test.exs`

| Old case | Native replacement |
| --- | --- |
| uses Chain-of-Draft default prompt | [uses Chain-of-Draft default prompt](../../test/jido_ai/strategy/chain_of_draft_test.exs) |
| routes ai.cod.query and delegated worker events | [routes ai.cod.query through the shared session and owns its worker](../../test/jido_ai/strategy/chain_of_draft_test.exs) |
| cod_start emits CoT worker spawn directive | [start commits one pending request before model work](../../test/jido_ai/strategy/chain_of_draft_test.exs) |
| request_completed event extracts #### final answer | [request completion extracts #### final answer](../../test/jido_ai/strategy/chain_of_draft_test.exs) |
| request_failed worker event transitions to error state | [provider failure stores its cause and releases the request](../../test/jido_ai/strategy/chain_of_draft_test.exs) |
| busy second request emits request error directive | [busy second request returns a correlated failure without replacing the first](../../test/jido_ai/strategy/chain_of_draft_test.exs) |

### `test/jido_ai/cot_agent_test.exs`

| Old case | Native replacement |
| --- | --- |
| defines expected helper API | [defines expected helper API](../../test/jido_ai/cot_agent_test.exs) |
| uses ChainOfThought strategy | [selects ChainOfThought in the native AI profile](../../test/jido_ai/cot_agent_test.exs) |
| uses expected defaults when not provided | [uses expected defaults when not provided](../../test/jido_ai/cot_agent_test.exs) |
| passes custom model and system_prompt options to strategy | [passes custom model and system_prompt options to strategy](../../test/jido_ai/cot_agent_test.exs) |
| resolves system_prompt from module attribute | [resolves system_prompt from module attribute](../../test/jido_ai/cot_agent_test.exs) |
| treats false system_prompt as omitted | [treats false system_prompt as omitted](../../test/jido_ai/cot_agent_test.exs) |
| treats nil system_prompt as omitted | [treats nil system_prompt as omitted](../../test/jido_ai/cot_agent_test.exs) |
| raises when module attribute system_prompt does not resolve to a binary | [raises when module attribute system_prompt does not resolve to a binary](../../test/jido_ai/cot_agent_test.exs) |
| on_before_cmd marks request as failed on cot_request_error | [busy admission returns the rejected request ID and keeps active work](../../test/jido_ai/cot_agent_test.exs) |
| on_after_cmd finalizes pending request on terminal delegated worker event | [completion commits the request and public result fields](../../test/jido_ai/cot_agent_test.exs) |
| on_after_cmd stores request meta from completed strategy snapshots | [completion stores usage from the provider response](../../test/jido_ai/cot_agent_test.exs) |
| on_after_cmd marks pending request failed on terminal failure snapshot | [failure stores the provider cause and closes the pending request](../../test/jido_ai/cot_agent_test.exs) |
| documents request lifecycle behavior for think/await helpers | [documents request lifecycle behavior for think/await helpers](../../test/jido_ai/cot_agent_test.exs) |

### `test/jido_ai/cod_agent_test.exs`

| Old case | Native replacement |
| --- | --- |
| uses ChainOfDraft strategy | [selects ChainOfDraft in the native AI profile](../../test/jido_ai/cod_agent_test.exs) |
| uses expected defaults when not provided | [uses expected defaults when not provided](../../test/jido_ai/cod_agent_test.exs) |
| passes custom model and system_prompt options to strategy | [passes custom model and system_prompt options to strategy](../../test/jido_ai/cod_agent_test.exs) |
| resolves system_prompt from module attribute | [resolves system_prompt from module attribute](../../test/jido_ai/cod_agent_test.exs) |
| treats false system_prompt as default prompt | [treats false system_prompt as default prompt](../../test/jido_ai/cod_agent_test.exs) |
| treats nil system_prompt as default prompt | [treats nil system_prompt as default prompt](../../test/jido_ai/cod_agent_test.exs) |
| raises when module attribute system_prompt does not resolve to a binary | [raises when module attribute system_prompt does not resolve to a binary](../../test/jido_ai/cod_agent_test.exs) |
| on_after_cmd keeps last_result string while request failure stores raw term | [failure keeps last_result printable and stores the provider error](../../test/jido_ai/cod_agent_test.exs) |

## Validation

- Before the stream fix: 50/52 passed. The complete image delta and wrapper
  lifecycle documentation checks failed.
- After the stream fix and API documentation update: all 52 passed in 6.6 seconds.
- These files accounted for 39 failures in the previous full root result.
- The full package and example results are recorded in the
  [root package checkpoint](root-package-checkpoint.md).

The new image examples extend `09_01_linear_test.exs`. They run only when
integration tests are included. The existing history ledger and API inventory
remain unchanged. This transfer does not close any history row.

Logs: `/tmp/jido-ai-v3-linear-root-test-02.log` and
`/tmp/jido-ai-v3-linear-root-test-03.log`.
