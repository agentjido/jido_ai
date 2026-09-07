# Standalone runner test transfer: callbacks and output repair

This pass moves 14 retained cases in the [root runner test](../../test/jido_ai/react/runtime_runner_test.exs)
to the shared HTTP/SSE MockLLM. Real ReqLLM, Action, Flow, Agent and Session
code processes each request. All 58 original test names remain. One separate
HTTP credential test raises the file count to 59. No cases were removed,
combined or skipped. The [case list](runner-test-transfer.json) records this scope.

The complete root run passes 1,948/2,397 cases, with 449 failures and one
existing exclusion. The previous checkpoint had 462 failures. The comparison
has 13 resolved failures and no new failure. The ordered-event case already
passed; it now uses real HTTP. The separate HTTP credential case is new.
The remaining 28 runner failures are required migration work.

## Retained cases now using HTTP

1. `streams multimodal user content to ReqLLM`.
2. `emits ordered event envelopes for a final-answer run`.
3. `retains generated images in stream deltas and the final result`.
4. `replays generated images and thinking as flat content on the next tool round`.
5. `after_tool_call callback transforms the canonical tool result`.
6. `optional before_tool_call callback can rewrite tool arguments`.
7. `tool guardrail validates arguments after before_tool_call rewrites them`.
8. `validates structured output before request completion`.
9. `repairs invalid structured output with tools removed from repair call`.
10. `structured output does not transform a repair request when parsing succeeds`.
11. `structured output repair propagates request_transformer errors`.
12. `structured output transforms every repair attempt`.
13. `structured output transformer receives and overrides the exact repair request`.
14. `structured output repair rejects invalid transformed messages before the provider call`.

## Shared production fixes

- The standalone adapter binds callbacks from `context.agent_module` to the
  native profile interceptor. The private Agent keeps its own runtime identity.
  The shared tool path applies before and after callbacks. Input guardrails
  receive the arguments after the before callback.
- Request-transform errors retain their cause and record
  `error_type: :request_transform` through Session failure metadata.
  Invalid transformed messages stop before another provider call.
- A provider error during output repair uses the remaining output attempts.
  It counts the attempted model call and retains available prior usage.
  Initial provider errors and transform/control errors remain terminal.
  The existing Flow owns the next attempt; there is no second retry loop.
- Saved repair failures use `Jido.AI.Error.for_storage/1`. Raw provider errors
  can contain live SDK state and improper lists. Those values cannot enter
  a portable checkpoint. A real 503 followed by successful repair proved this
  gap and the fix.

The new HTTP credential test checks `Authorization` on both real requests.
Callback fixtures use the supplied runtime state to identify repair. They do
not depend on process-local counters across separate core Action tasks.

## Eight added integration cases

[14_02](../../examples/v3/profiles/14_02_standalone_runtime.md) adds six cases:
before-only, after-only and combined tool callbacks; callback failure; invalid
transformed messages; and provider-error recovery with a portable token.
They check callback inputs, actual Action arguments, correlated tool JSON,
terminal output metadata, call counts and saved token state. The token does
not contain the test API key.

[02_06](../../examples/v3/profiles/02_06_output_contract.md) adds two native
Agent cases: repair recovery and exhaustion after a provider error. Both use
an explicit two-attempt budget and make three HTTP calls including the initial
invalid answer. The retained one-provider-error case now explicitly selects
one repair attempt. It keeps its original assertions. The larger budget has
separate recovery and exhaustion proof.

## Contract details and open cases

The request-start event retains the typed multimodal query. The old text
preview is replaced by typed content; the test checks those exact parts and
the actual HTTP image URI. Image delta events also carry the model label.
Flat image content and reasoning content reach the next provider request.

For a model override to `gpt-4.1`, ReqLLM selects the Responses API. The exact
repair test checks `/v1/responses`, the two encoded input messages and the
model. Business tools are absent from the callback request. ReqLLM can add its
own `structured_output` schema tool to encode the requested object. The test
checks its schema and proves that the business Calculator tool is absent.

Two original cases remain failing and required:

- Numeric-string usage: the original stream case supplies `"3"` and `"1"`.
  A native HTTP probe also produced zero through the current decoder. Integer
  usage is not proof of this contract. Source selection must preserve explicit
  zero and distinguish unavailable usage from a decoder default. See the
  [source-order review](history-reviews/12-observation-and-token-reporting.md).
- AWS credentials: the original transform case supplies `access_key_id` and
  `secret_access_key`. The new HTTP API-key test does not prove these options.
  The original AWS fixture and case remain. Correct provider-boundary proof
  is required; OpenAI correctly rejects AWS-specific request options.
  ReqLLM 1.22 uses the optional `ex_aws_auth` package for IAM signing. This
  project does not yet declare that optional dependency. The provider check
  must use actual signing and the shared local transport, including the
  correct Bedrock request and response forms.

An intermediate full run reported 1,949/2,396 passed and 447 failed. Review
found that two rewritten inputs no longer proved the original requirements.
Those original cases were restored, and the distinct API-key case was added.
The final full root result above replaces that intermediate result.

The immutable API inventory and all release-history source-review fields are
unchanged. No history row was closed. Remaining package and release gates
are still open.

Root log: `/tmp/jido-ai-v3-root-test-26.log`.
Failure comparison: `/tmp/jido-ai-v3-root-checkpoint-06-failures.json`.
Focused example log: `/tmp/jido-ai-v3-standalone-repair-examples-01.log`
(43 passed).

The final full example run passes all 1,139 cases in 149.1 seconds, including
integration and pending-DSL tags. Its log is
`/tmp/jido-ai-v3-acceptance-runner-repair-final-02.log`. The first repeat had
one ToT test timer-delivery failure. Only its assertion wait changed; the
20 ms production search limit and duration assertions remain. The forced
full production compile passes for 229 AI files with warnings as errors.

The later [stream usage pass](stream-usage-port.md) restores the original
numeric-string decoded-chunk test without an input change. It retains the
separate required HTTP failures in ReqLLM. The AWS credential case remains open.
The earlier test counts in this document record the callback/repair checkpoint.

## Later provider pass

The [provider transfer](provider-test-transfer.md) moves four more retained
cases to real HTTP and resolves three failures. It keeps every original
runner case. It also adds two shared mock contracts, four integration cases,
and three response-boundary cases. The counts above describe the earlier
callback and repair checkpoint.
