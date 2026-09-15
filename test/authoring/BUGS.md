# AI authoring findings

Found against the local V3 foundation at `c0e8d9c1`, with sibling core
Jido 3.0.0-beta.1. Findings 001–009 are resolved in the working tree.
The original observations are retained. The current tests assert corrected
behavior, not the original faults. No findings are skipped.

The five original findings have active tests in
[known_bugs_test.exs](agents/known_bugs_test.exs). These tests now assert the
intended contract, not the original fault. Default-suite regression tests in
`test/jido_ai/authoring/regressions_test.exs` also cover invalid input, direct
turn/session calls, and local HTTP calls through the public helpers.

Run all five regression tests:

```sh
mix test test/authoring/agents/known_bugs_test.exs --only authoring --seed 0
```

| ID | Impact | Finding |
| --- | --- | --- |
| AI-AUTH-001 | Medium | AI wrapper prevents block metadata |
| AI-AUTH-002 | Medium | Model shorthand differs between profile construction and source lowering |
| AI-AUTH-003 | Low | Keyword profile input differs between construction and source lowering |
| AI-AUTH-004 | High | Turn-mode public helper drops caller context |
| AI-AUTH-005 | Medium | Native direct execution fails with an internal missing-context error |
| AI-AUTH-006 | Medium, resolved | Block metadata conflicts with `max_state_size` |
| AI-AUTH-007 | Medium, resolved | Public export raises for rich model records |
| AI-AUTH-008 | High, resolved | Core instantiation bypasses the authored AI state-size limit |
| AI-AUTH-009 | High, resolved | Required MCP tool source is silently absent at runtime |

## AI-AUTH-001: block metadata does not compile through the AI wrapper

Trigger: use `Jido.AI.Agent` and declare `metadata` inside `agent do`,
without keyword metadata.

Observed: compilation raises
`Fields declared in both keyword and block form: [:metadata]`.
The same declaration with `use Jido.Agent, extensions: [Jido.AI.DSL]` compiles.

Cause: [Agent.Definition](../../lib/jido_ai/agent/definition.ex) always injects a
keyword metadata map, including when the author did not supply one.
Core correctly detects a conflict with the block declaration.

Expected: an author-supplied block is the only metadata declaration in this
case. Existing explicit conflicts must still fail.
Current workaround: keyword metadata, or the core Agent with the AI extension.
Fixtures: `fixtures/metadata_block.exs` and `fixtures/metadata_core.exs`.

Resolution: the wrapper no longer injects empty keyword metadata. Block
metadata compiles; explicit keyword/block conflicts still fail. The later
AI-AUTH-006 fix also makes `max_state_size` work with either metadata form.

## AI-AUTH-002: model shorthand is rejected by source lowering

Trigger: pass `%{id: :assistant, model: model, result: %{into: :reply}}`
through both public construction paths.

Observed: `Profile.new/1` accepts it and the resulting Profile lowers.
Passing the same raw source to `Authoring.lower/2` or
`Authoring.Codec.encode/2` fails with `profile: Unknown field :model`.

Cause: [Profile.source/1](../../lib/jido_ai/profile.ex) validates a field list
that includes `:routes` but omits the `:model` shorthand accepted by
`Profile.new/1`. The DSL shorthand itself works.

Expected: a consistent shorthand at source boundaries, or an explicit
documented restriction. This is an API consistency gap, not a model-call fault.
Current workaround: use `models: %{default: %{model: model}}`, or construct
a Profile before lowering.

Resolution: source validation accepts `model` and delegates normalization to
`Profile.new/1`. Raw source, Profile values, and source Codec paths agree.

## AI-AUTH-003: keyword profile input is rejected by source lowering

Trigger: pass the same profile fields as a keyword list.

Observed: `Profile.new/1` accepts the keyword list. Passing that Profile to
the lowerer succeeds. Passing the raw keyword list to the lowerer fails with
`profile: Expected a map`.

Cause: `Profile.source/1` runs map field validation before the keyword
normalization used by `Profile.new/1`.

Expected: a consistent input contract, or a clearly documented restriction.
This is an API consistency gap. Keyword **Agent attributes** already work.
Current workaround: normalize the profile with `Profile.new/1` first.

Resolution: source input uses the same keyword normalization as `Profile.new/1`.
Duplicate fields, unknown fields, and improper lists remain invalid.

## AI-AUTH-004: turn-mode ask drops the caller's context

Trigger: call an authored turn Agent with
`AgentModule.ask(server, query, context: context, timeout: timeout)`.

Observed: [Agent.Interface.ask/4](../../lib/jido_ai/agent/interface.ex) invokes
`AgentServer.call/3` with only `timeout:`. The caller's context is absent.
Session-mode helpers retain it.

Impact: provider endpoint, request options, credentials supplied in context,
tool context, and other caller data can be lost. The resulting request may fail
or use configured defaults instead of the caller's intended configuration.

Expected: the helper carries the authorized caller context to AgentServer.
The reproduction captures the call boundary with Mimic, so it cannot send a
provider request accidentally.
Current workaround: the generated core route helper, or
`AgentServer.call/3` with an explicit context. Both are exercised by the suite.

Resolution: turn helpers pass caller context to AgentServer. A local HTTP test
checks both `ask/3` and `ask_sync/3` with caller-supplied provider options.

## AI-AUTH-005: direct native AI execution reports an internal KeyError

Trigger: instantiate the native AI definition and call
`Jido.Agent.cmd(agent, signal, context: provider_context)`.

Observed: an `ExecutionFailureError` contains
`details.jido_ai_cause == %KeyError{key: :jido_ai_profiles, ...}`.
No model request occurs. The same case and context work through AgentServer.

Cause: the native runtime assembles profile context from the AgentServer
Plugin runtime input. Direct Agent execution does not supply that input.

Expected: either supported direct execution or an explicit, stable error
that says this route requires AgentServer. An internal missing-key exception
does not state that boundary. This finding does not assume that session
workers can run without an OTP runtime.
Current workaround: execute the native route through AgentServer.

Resolution: native direct turn and session calls return a validation error on
field `runtime`: `Native AI routes require AgentServer admission; use
Jido.AgentServer.call/3`. No model work starts. This is an explicit runtime
boundary, not new support for direct execution. Plugin preparation supplies
the marker used to detect this boundary without adding application state.

## Resolved findings from the expanded suite

These four tests remain in `agents/open_findings_test.exs` to keep review links
stable. They now assert the corrected contracts. The default suite also tests
these fixes in `test/jido_ai/authoring/resolved_findings_test.exs`.

## AI-AUTH-006: block metadata conflicts with a state-size option

Trigger: `use Jido.AI.Agent, max_state_size: 4096` together with block metadata.
Compilation raises the core duplicate keyword/block metadata error.

Cause: the wrapper still encodes `max_state_size` by adding keyword metadata.
The fix for 001 removed only the unconditional empty metadata injection.

Expected: user metadata and the size option compose without a false duplicate
declaration. Explicit user keyword/block conflicts must still fail.
Workaround: put user metadata in the keyword options when using this limit.

Resolution: a Spark transformer adds the size limit to the selected metadata
form before core lowering. Block metadata and keyword metadata both work.
Explicit keyword/block metadata conflicts are still rejected.

## AI-AUTH-007: rich model records raise during public export

Trigger: export a valid Agent whose model is a `ReqLLM` model record with
`Jido.AI.export/3` in map, JSON, or YAML form.

Observed: `Protocol.UndefinedError` for `Enumerable` on the model record.
The same profile lowers and executes, and the core Codec can preserve the
record through a registered value.

Cause: `Portable.portable_model/1` falls through to generic map conversion,
which tries to enumerate the struct.

Expected: a supported portable model representation, or a structured export
error that explains the restriction. Workaround: use a model ID for public
export, or use core Codec with a host-owned Registry for rich records.
The positive public-format tests use model IDs and still execute real local
HTTP requests after import.

Resolution: public export returns a structured `Validation.Invalid` error at
`models.<role>.model` for rich model records, with directions to core Codec.
This avoids both an exception and silent loss of model options. It does not
add a new public rich-model wire format.

Scope decision: public rich-model export is dropped. Core Codec supports only
generic registered-value references here, not model-specific export. Keep the
structured rejection and its tests; no new model Registry format is planned.

## AI-AUTH-008: construction does not enforce the authored state-size limit

Trigger: lower an Agent with AI size metadata of 4096 bytes, then instantiate
it through `Jido.Agent.instantiate/2` with a 5000-character result field.

Observed: instantiation succeeds and the external state size exceeds 4096.
`Jido.AI.Agent.from_initial_state/2` rejects the identical input with
`Agent state exceeds max_state_size`.

The first investigation attributed this to the core construction path. Further
testing found the actual cause in the AI refinement callback: Zoi reserves MFA
functions named `validate` for protocol dispatch. It passed schema, state, and
limit to a function expecting state, limit, and context. Erlang term ordering
then allowed the size comparison against a map to succeed.

Expected: the authored limit holds across supported construction paths.
Resolution: new schemas use a distinct `check` callback. The old `validate` MFA
also accepts the correct protocol argument order for stored schemas. Tests
cover exact byte limits, Plugin-owned state, core construction, Builder and
Codec, direct state updates, and rejection of oversized model output without a
commit. No core Jido change was required.

## AI-AUTH-009: required dynamic tool source is silently ignored

Trigger: author an MCP tool source with `required: true`, `discover: true`, and
an unconfigured endpoint. Lowering retains the source in the profile.

Observed: native execution sends a model request with no tools and returns a
successful answer. It does not reject the missing required source. No external
MCP service is involved; the model endpoint is the local test server.

The source declarations are validated and serialized, but native runtime code
does not consume `profile.tool_sources`.

Expected: resolve the required source, or fail before the model call with a
clear unsupported-source or unavailable-source error. Silent omission makes
the authored requirement ineffective. Workaround: supply resolved static tools
and do not rely on native dynamic source declarations yet.

Resolution: native requests selecting a profile with dynamic tool sources
return a structured `tool_sources` validation error before model work. This
applies to turn and session modes and required or optional declarations. Other
profiles and configuration routes remain usable. Source authoring and transport
remain supported; runtime adapter resolution is not implemented by this fix.
