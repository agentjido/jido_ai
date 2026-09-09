# ReAct request setup test transfer

The [root ReAct Strategy file](../../test/jido_ai/strategy/react_test.exs) keeps
78 cases. The setup pass transferred 24 to native Agent, Flow, Configuration,
Request and Session APIs. At that checkpoint, the other 54 remained required
and failing. The later [lifecycle pass](react-lifecycle-test-transfer.md) moves
24 more cases. The [context pass](react-context-test-transfer.md) moves another
18; the current result is 66 passed and 12 required failures. No case was removed,
combined or skipped. The [complete case map](react-setup-test-transfer.json)
accounts for every original name against the pinned source commit.

## What the checks prove

Most old setup cases inspected a deferred worker payload before any model call.
Their native cases inspect the prepared request at a declared model control.
The control returns `{:error, :configuration_observed}` after capture. The empty
shared mock script must receive no request. This proves option preparation and
control order; it does not claim provider acceptance of arbitrary options.

Four transferred cases use actual HTTP to check no system prompt, request
admission before worker activity, buffered generation, and the token limit.
The admission case holds the response, inspects the pending record and native
worker, then proves one completed model call. Definition checks retain invalid
policy, transformer and prompt rejection. The tool cases check both the bound
catalog and prepared ReqLLM definitions. Unknown tools fail before admission.

## Source-to-v3 changes

- Removed Strategy `init`, `cmd`, child-start payloads and worker channels map
  to validated definitions, native routes, the Session control point, and an
  owned model worker. No old core Strategy runtime was added.
- Old direct-Strategy `system_prompt: false` meant no prompt. Native profiles
  express this as explicit `instructions: nil`; the HTTP case proves no system
  message. The public Agent macro keeps its own default-prompt behavior.
- ReAct query, cancel, prompt and context routes remain available. Native
  steering and injection use `Session.steer/3` and `Session.inject/3`, which send
  the common `jido.ai.session.control` signal with a kind. The old worker
  lifecycle routes are removed. This maps route behavior; it does not restore
  every old raw signal spelling.
- Unknown allowed tools now return the structured admission error and create no
  request record. The old `EmitRequestError` Directive is not recreated.
- The model-control fixture includes the shared mock transport options. Exact
  option-set assertions include those declared fixture defaults. Unknown option
  names still produce no atom, nil key, or extra option.

## Shared fixes and refinement

Agent option maps now use the same safe option-name conversion as standalone
ReAct. The definition accepts keywords and ordinary maps; invalid containers
still fail. Inner provider options are normalized after the request resolves
its model. An initial implementation resolved aliases during compilation and
failed on aliases supplied at runtime. The refined implementation converts
names first and defers provider lookup. It reuses the shared normalizer and
keeps unknown-key filtering and existing-atom behavior.

Explicit request HTTP options first merge with runtime context options. The
shared preparation path then combines that result with declared model HTTP
options. Request keys take priority. An empty request keyword list retains
defaults. Session and direct Turn execution use the same helper. This is a merge of HTTP option keys, not a deep merge of
headers or other option values. A supplied headers list replaces that value.
Per-call provider option replacement remains separate and unchanged.

The [02_26 integration examples](../../examples/02_requests/02_26_request_setup/README.md)
provide six checks for header preservation, callback execution for buffered
Session calls, selected generation values, the next request's defaults and
portable state. Native Session, native Turn and public Agent modes each run
with streaming on and off. They use one
shared server. Streamed calls use ReqLLM's Finch path; these examples do not
claim that its streaming path invokes a custom Req adapter.

## Transferred cases

| Original case | Native case |
| --- | --- |
| raises for unsupported request_policy values | definition rejects unsupported request policy |
| raises for invalid request_transformer values | definition rejects an unloaded request transformer |
| treats false system_prompt as no prompt for direct strategy callers | explicit nil instructions preserve the old direct no-prompt behavior |
| raises for non-binary system_prompt values | definition rejects a non-text system prompt |
| routes delegated worker signals and compatibility observability signals | native routes bind ReAct and ignore compatibility observations |
| start lazily spawns worker and stores deferred start payload | start commits one request before its owned model worker runs |
| start propagates streaming option into runtime config | start uses buffered HTTP when streaming is disabled |
| start propagates max_tokens option into runtime config | start sends the configured token limit over HTTP |
| start preserves configured max_iterations when request omits override | prepared request keeps the declared iteration limit |
| start applies request-scoped max_iterations override to runtime config | prepared request uses its iteration override |
| start ignores invalid request-scoped max_iterations override | invalid iteration override keeps the declared limit |
| start propagates stream_timeout_ms option into runtime config | prepared request keeps its declared idle timeout |
| start applies request-scoped stream_timeout_ms override to runtime config | prepared request uses its idle timeout override |
| start applies request-scoped stream timeout override to runtime config | request idle timeout overrides the legacy receive timeout alias |
| start merges base and run req_http_options into runtime config | prepared request merges declared and request HTTP options |
| start merges base and run llm_opts into runtime config | prepared request merges declared and request generation options |
| start applies request-scoped allowed_tools filter to runtime config | prepared request applies the allowed tool filter |
| start applies request-scoped tools override to runtime config | prepared request uses the request tool catalog |
| start applies request-scoped request_transformer override to runtime config | request transformer override runs before the model control |
| start rejects unknown allowed_tools with request error directive | unknown allowed tools fail admission before model work |
| start accepts string-key llm_opts maps and normalizes ReqLLM options | prepared request normalizes string generation option names |
| start maps existing-atom string llm_opts keys for provider options | prepared request retains an existing atom option name |
| start drops non-existing string llm_opts keys and filters nil keys | prepared request drops unknown option names without atom creation |
| start normalizes provider_options maps in llm_opts using provider schema keys | prepared request normalizes provider option keys by schema |

The focused root result is 24/78 passed, with 54 required failures. All 24
transferred cases pass. The complete root and acceptance results will be
recorded in the [package checkpoint](root-package-checkpoint.md). No history
row is closed by this pass; provider-specific option contracts remain required.

The initial HTTP run exposed the empty-override path: a later request lost its
declared headers when only context defaults were present. Moving the merge to
shared preparation fixed this for Session and direct Turn execution. The final
six focused cases pass. Earlier fixture corrections removed a remote function
call and a module attribute from public macro options, which require literals.
The examples now use a runtime model alias and literal streaming values.

The refinement pass also removed unused state and full-context capture from
the setup fixture. It captures only the prepared request and selected profile.
The final focused root run remains 24/78 passed, with all 24 replacements
passing. Logs: `/tmp/jido-ai-v3-react-setup-06.log` and
`/tmp/jido-ai-v3-request-setup-examples-07.log`.

The complete root run passes 1,998/2,412 cases in 24.9 seconds, with 414
failures and one existing exclusion. All four doctests pass. The comparison
resolves exactly the 24 mapped cases and has no new failing case. All 54
unported ReAct cases remain failing. Log: `/tmp/jido-ai-v3-root-test-30.log`.
Failure inventory: `/tmp/jido-ai-v3-root-checkpoint-10-failures.json`.

The full production compile passes for all 230 files with warnings as errors.
The source model alias is resolved only at runtime; no fixture alias was added
to production configuration. No core dependency files changed.

The complete acceptance run passes 1,171/1,175 cases in 149.4 seconds, with
four required ReqLLM usage failures and no exclusions. All six new examples
and prior 1,165 passing cases pass together. Log:
`/tmp/jido-ai-v3-acceptance-request-setup.log`. No dependency code changed.
The prior core timing failure remains an open finding although it did not
repeat in this run. The migration goal remains active.

The later [tool inspection pass](react-inspection-test-transfer.md) moves two
more retained cases. ReAct now passes 68/78, with ten required failures.

The later [initial-state transfer](react-initial-state-test-transfer.md) moves
four more retained cases. ReAct now passes 72/78, with six required failures.
