# Incomplete response port

The [02_25 examples](../../examples/02_requests/02_25_incomplete_response/README.md)
cover blank provider failure, accepted partial content, saved history, usage,
and terminal tokens through native Agent DSL and standalone requests.

The shared model operation already rejected failed blank responses before
successful history and model events, but did not record the retained
`error_type: :llm_response`. It also checked only text, tool calls and objects.
An image-only response with a truncated finish reason therefore failed despite
having usable content. The terminal check now uses the existing
`Jido.AI.Turn.result/1` projection and records the failure type through Session.
There is no second provider parser or broader default content rejection.

The retained runner case `blank truncated terminal responses fail before
llm_completed and after_llm checkpoint emission` now passes unchanged. Its
assertions check the exact length cause, failure type, usage, missing success
events, terminal token and history. The runner file now passes 42/59 cases,
with 17 failures. All original names and assertions remain in this pass.

The 16 new HTTP/SSE cases initially had fixture errors: native history was
not declared, and they expected the Chat decoder to preserve unsupported
finish-reason strings. The corrected fixture declares history and makes the
SDK mapping explicit. Its baseline passed 4/16 cases. Ten failures proved the
missing failure type; two proved the partial-image rejection. After the shared
fix all 16 pass. Partial text and blank successful stop still pass.

These checks do not replace the five required legacy error-envelope failures,
the exact Responses status cases or typed partial-output requirements. The
current generated Agent helper returns a raw cause where those old tests
expect `{:failed, :error, cause}`. No test was rewritten to hide that difference.
No history row is closed and the immutable API baseline remains unchanged.

Focused logs: `/tmp/jido-ai-v3-incomplete-response-02.log`,
`/tmp/jido-ai-v3-incomplete-response-03.log`, and
`/tmp/jido-ai-v3-incomplete-runner-01.log`.

The complete root run passes 1,974/2,412 cases in 24.8 seconds, with 438
failures and one existing exclusion. All four doctests pass. The comparison
resolves only the unchanged blank-response case and introduces no new failing
case. Log: `/tmp/jido-ai-v3-root-test-29.log`. Failure inventory:
`/tmp/jido-ai-v3-root-checkpoint-09-failures.json`.

The complete acceptance run passes 1,165/1,169 cases in 147.4 seconds, with
four required ReqLLM usage failures and no exclusions. All 16 new response
cases pass with all prior 1,149 passing cases. The earlier core shutdown timing
error did not repeat, but remains an open dependency finding. Log:
`/tmp/jido-ai-v3-acceptance-incomplete-response.log`. The full forced compile
passes for 230 production files with warnings as errors.
