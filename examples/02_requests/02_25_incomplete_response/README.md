# 02_25: Blank failures and partial response content

The [native Agent](agent.ex)
declares its model, session, saved history and result field through `agent do`.
The [16 example cases](../../../test/examples/02_requests/02_25_incomplete_response/02_25_incomplete_response_test.exs)
use this Agent and the standalone ReAct API. They run the real ReqLLM Chat
stream decoder against the shared model server. No live provider is required.

```sh
mix test test/examples/02_requests/02_25_incomplete_response/02_25_incomplete_response_test.exs --include example
```

Ten cases send blank responses with five finish-reason strings through both
APIs. The current Chat decoder maps `incomplete`, `error` and `cancelled` to
`:error`; it retains `length` and `content_filter` as their corresponding atoms.
The tests state that mapping. These are canonical Chat error checks, not proof
that the Responses API preserves its exact incomplete/cancelled status.

Each blank failure retains usage, emits one failure with
`error_type: :llm_response`, and saves only the user input. There is no successful
model-completed event, request completion or after-model checkpoint. The
native result field stays unchanged. Standalone execution emits a portable
failed terminal token with the same cause and usage.

Four cases accept actual partial text and generated image bytes with a `length`
finish reason. They retain the provider reason in the model event and save the
usable answer. This preserves the existing rule that visible partial content
can complete without a typed-output constraint. Two cases retain the separate
blank successful `stop` behavior.

The shared terminal check now uses `Jido.AI.Turn.result/1`, as other result
paths already do. It sets the failure type before returning a failed blank
response. This fixes the retained root blank-response test without changing
its input or assertions. The first valid fixture run passed 4/16 cases: ten
were missing failure type and two rejected partial images. All 16 now pass.

## Limits

The original root wrapper tests still require the legacy
`{:failed, :error, cause}` envelope. Five such tests remain failing because the
current generated Agent helper returns the raw cause. This pass does not change
those tests or claim their API contract is preserved. Exact Responses status
handling, typed partial-output validation and failed transport continuation
remain separate required checks in [history review 07](../../../docs/v3-spike/history-reviews/07-streams-and-checkpoints.md).
No history row is closed by this example.
