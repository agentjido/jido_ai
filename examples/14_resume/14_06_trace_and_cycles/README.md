# 14_06: Trace controls and repeated tool calls

[Agent](agent.ex) and
[tests](../../../test/examples/14_resume/14_06_trace_and_cycles/14_06_trace_and_cycles_test.exs) use the real
native Flow, Session, provider decoder and tools. The shared MockLLM server
supplies all model responses. The 10 cases are example tests, excluded by
default and run with `--include example`.

## Trace and tool events

`ReAct.Config.new/1` takes flat options. `capture_deltas?` becomes the native
`observability.emit_llm_deltas?` flag. When false, no delta events are emitted
and standalone State stream fields stay empty. Complete model responses,
results and execution history remain available. When true, `streaming_text`
and `streaming_thinking` accumulate decoded deltas and reset at each model
start. A saved model checkpoint retains those fields. Resume can finish an
already decoded answer without a new model request.

There is no standalone State `thinking_trace` field. Parent Agent metadata has
a separate trace API.

`redact_tool_args?` becomes `observability.redact_tool_args?`, default true.
The native Agent DSL accepts that flag in its existing observation map.
The Session applies the existing sensitive-key sanitizer to
`tool_started.data.arguments`. Arguments reflect the before-tool callback,
before Action schema conversion. Actual tool inputs remain complete.
The tests check explicit nested redaction markers and unchanged real inputs.

This is a tool-start event contract. Full `llm_completed.tool_calls`, model
history and execution checkpoint data are not filtered by this flag. Telemetry
and tool-result transport retain their separate existing sanitizer boundaries.

## Repeated calls

The common Flow checks a completed tool round. It compares public tool names
and full original model arguments, before tool callbacks. Call IDs and order
do not affect this check. Repeated calls still execute. The warning is a user
message before the next model request; it asks the model to use the results
or change its approach. No extra input-injection event is added.

The old implementation used truncated `inspect/1` output for comparison.
The port hashes deterministic full terms. Long inputs with different suffixes
stay distinct. Two public names for the same Action also stay distinct.
The warning no longer claims that tool results are equal: neither version
compares results.

The signature lives in native tool metadata and is projected to standalone
State. The Session retains it on a later model failure. The checkpoint keeps
that metadata and the warning together. The old Runner saved the checkpoint
before it saved the signature and warning. Two consecutive resume cases now
prove one warning in the next model request and no replay of completed tools.
Wrong-run observations cannot change a request's signature.

This comparison existed before the initial 2.0 release, in commit `eb2279fa`
(PR 188). It is baseline feature evidence, not a new post-2.0 audit row.
The redaction cases add related execution evidence for PR 300's sanitizer.

## Validation and remaining work

Run from the repository root:

```sh
mix test --include example --seed 0 test/examples/14_resume/14_06_trace_and_cycles/14_06_trace_and_cycles_test.exs test/examples/14_resume/14_03_checkpoint_resume/14_03_checkpoint_resume_test.exs test/examples/14_resume/14_05_worker_lifecycle/14_05_worker_lifecycle_test.exs test/examples/02_requests/02_07_response_metadata/02_07_response_metadata_test.exs test/examples/02_requests/02_12_tool_callbacks/02_12_tool_callbacks_test.exs
```

The focused set passes 82 checks. See the
[implementation record](../../../docs/v3-spike/implementation.md) for design
history. Parent trace retention and inspection, context lanes and compaction,
provider variants, and durable recovery are outside this example.
