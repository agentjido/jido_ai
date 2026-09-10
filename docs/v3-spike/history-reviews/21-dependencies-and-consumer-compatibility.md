# History review 21: dependencies and consumer compatibility

Reviewed on 2026-09-06 against `fc5bc1434ddb69493fe8a68443f03bc6a198c5a2`.
This pass completes the last 29 source reviews. All 126 commits and all 103
associated merged PRs now have source reviews. All v3 port checks remain pending.

Read each complete commit message, each changed file outside `mix.lock`, and
every changed lock entry. Check package identity, version, build tool, dependency
ranges, optional flags and checksums. The structured ledger stores those lock
entries with their commit. The Git links retain the complete original diffs.
Read all 20 associated PR bodies and their captured comments and reviews.
No runtime tests were run in this pass. No production files were changed.

## User feedback and scope

[Issue 212](https://github.com/agentjido/jido_ai/issues/212) reports a real
transport difference: a custom adapter added headers to normal requests, but
streaming used a separate Finch path and lost the headers. The user also asked
for consistent access to HTTP options. The three comments trace the fix to
[ReqLLM PR 566](https://github.com/agentjido/req_llm/pull/566) and ReqLLM 1.9.
That PR supplies a configured Finch adapter, then a per-request callback.
Commit `8f669705` closes the report through the dependency update.

The current ReAct tests check `req_http_options` and model options through
stubs. They do not prove that headers reach an HTTP server. Add the real request
case below. Retain existing public option entry points; document any deliberate
extension to another method instead of assuming that it existed in v2.

[PR 330](https://github.com/agentjido/jido_ai/pull/330) records why the minimum
runtime must have its own check. A maintainer first parked the dependency update
until [ExAST PR 14](https://github.com/elixir-vibe/ex_ast/pull/14) restored declared
Elixir 1.18 support. A later comment records the released fix and local checks.
The upstream body reports Elixir 1.18/OTP 27 and Elixir 1.20/OTP 29 validation.
These are historical results. They do not prove the future v3 dependency graph.

PRs 252–256 have bot comments about missing dependency labels and maintainer
reviews that report checks on the combined maintenance state. Other Dependabot
PRs in this batch also have label notices. Keep the existing dependency workflow
check; historical comments do not establish the current label state. These
reviews are useful context, but are not separate v3 test runs.

The dependency PR bodies contain selected upstream release notes. Some excerpts
are explicitly truncated. This review covers every AI commit in the pinned
range, not every commit in ReqLLM or other dependencies. Preserve the provider
features that the supported AI API exposes. Do not turn every new upstream
provider or helper into a required AI feature or a second provider implementation.

## Per-commit decisions

Two candidate maintenance rows also require feature checks. `8f669705` now has
H01/H07 for stream headers. `7c2fea19` has H10 for the default Plugin test change.
The final classification is 81 behavior/refactor/test/documentation rows and
45 release-only rows. These are commit counts, not feature counts.

| Commit / PR | Source decision and context | Required cases |
| --- | --- | --- |
| [8f669705](https://github.com/agentjido/jido_ai/commit/8f6697052d6ecde5553e9a71fd94e2a1d2518481); no associated PR | ReqLLM 1.7.1 to 1.9.0; direct Dotenvy removed. Issue 212 describes headers lost through the streaming Finch path. Its three comments and upstream ReqLLM PR 566 define the fix. Existing ReAct tests assert forwarded options through stubs; they do not inspect actual headers. Preserve custom headers on normal and streaming model requests. ReqLLM 1.9 closes issue 212. Keep base and per-request HTTP options, ordered Finch request hooks and request isolation. The removal of direct Dotenvy must not make the CLI depend on incidental transitive packages. | `HIST-01/stream-headers`, `RELEASE/dependency-runtime`, `RELEASE/installer-compatibility` |
| [5ba86f43](https://github.com/agentjido/jido_ai/commit/5ba86f43d23dc0af3acdbb6d40eb83a1d007ebd7); no associated PR | Jido 2.1 to 2.2, Action 2.1.1 to 2.2 and Signal 2.0 to 2.1.1. Root Jido and Action requirements also change. No production API is added by this diff. Replace the Jido 2.2 dependency set with the coordinated v3 set. Preserve supported Agent and Plugin behavior; test a fresh consumer against compatible Action and Signal versions. | `RELEASE/dependency-runtime`, `HIST-17/plugin-choices` |
| [551d245a](https://github.com/agentjido/jido_ai/commit/551d245a6fe33e42a7a18c2f8cca66f062c5d210); [#252](https://github.com/agentjido/jido_ai/pull/252) | PR 252 updates Zoi 0.17.3 to 0.17.4. Its release notes describe inner option propagation for nullable values and schema pick/omit behavior. Review feedback reports combined maintenance validation; it is not v3 evidence. Retain valid nested and nullable schema metadata through the common output and tool schema path. Compile against the selected Zoi version. | `RELEASE/schema-error-compatibility`, `RELEASE/dependency-runtime` |
| [99c67902](https://github.com/agentjido/jido_ai/commit/99c679028df1cd124598dd6ba02a766ab2ce654f); [#253](https://github.com/agentjido/jido_ai/pull/253) | PR 253 names GitOps 2.9.3 to 2.10.0, but the lock diff also moves Igniter 0.7.7 to 0.7.9. GitOps notes add managed files and fix multiline commit parsing. Keep release preparation and generated notes compatible with GitOps. Verify the Igniter change included in this same commit through the installer package check. | `RELEASE/release-simulation`, `RELEASE/generated-notes`, `RELEASE/installer-compatibility` |
| [c8490d27](https://github.com/agentjido/jido_ai/commit/c8490d27d9e62feafff66d0d5f9c2067efa0ccb6); [#254](https://github.com/agentjido/jido_ai/pull/254) | PR 254 updates Credo 1.7.17 to 1.7.18. The release notes cover Elixir 1.20 compiler changes, tokens/sigils, umbrella dependency handling and an unused-map false positive. No AI behavior is introduced. Keep the final package warning-free and pass its configured lint checks on supported runtimes. | `RELEASE/current-type-checks`, `RELEASE/runtime-matrix` |
| [69cb1f5d](https://github.com/agentjido/jido_ai/commit/69cb1f5da8517f1497b0834f72c9885084c940bd); [#255](https://github.com/agentjido/jido_ai/pull/255) | PR 255 updates Splode 0.3.0 to 0.3.1. Release notes add error traversal and fix reserved-field warnings. Use the existing AI error contract; do not create another public traversal API. Preserve nested structured errors and useful exception summaries without compiler warnings. | `RELEASE/schema-error-compatibility`, `RELEASE/current-type-checks` |
| [a6ba0f8d](https://github.com/agentjido/jido_ai/commit/a6ba0f8d06d9f1ab1ad94ac5e26d37c2aa9fcdee); [#256](https://github.com/agentjido/jido_ai/pull/256) | PR 256 names Igniter 0.7.7 to 0.7.9, already present through 99c67902. The complete Git diff has no changed files. Release notes describe module index caching and reading the BEAM index instead of a private compiler interface. Record this empty commit as a duplicate dependency integration. Its package proof is shared with 99c67902; it does not introduce another feature. | `RELEASE/installer-compatibility` |
| [26bb4106](https://github.com/agentjido/jido_ai/commit/26bb4106d63fd33685c72012215e8e1a710e0497); [#261](https://github.com/agentjido/jido_ai/pull/261) | PR 261 updates ReqLLM 1.9 to 1.10 with JSV and LLMDB. Relevant upstream notes include property ordering, parallel tool calls, store/PDF handling, custom Finch selection, continuation IDs, structured stream timeout and malformed tool arguments. The upstream feature list is context, not a new AI API list. Preserve supported provider options, schemas, tool continuation, media and transport errors through the real ReqLLM adapter. | `RELEASE/provider-contracts`, `HIST-01/stream-headers`, `RELEASE/dependency-runtime` |
| [affe872c](https://github.com/agentjido/jido_ai/commit/affe872cc73d15890eb270d3b7e829d60ece5bc8); [#277](https://github.com/agentjido/jido_ai/pull/277) | PR 277 updates ReqLLM 1.10 to 1.11, SSE 0.2.1 to 1.0, JSV, LLMDB and Spitfire. Its release excerpt covers Responses reuse, nullable schemas, tool error flags, provider reasoning signatures, terminal stream errors and completed response items. The excerpt is truncated; it is not a complete upstream source audit. Retain supported reasoning/media content, terminal stream errors, final output and usage through the common provider boundary. | `RELEASE/provider-contracts`, `RELEASE/dependency-runtime` |
| [e71ee1b2](https://github.com/agentjido/jido_ai/commit/e71ee1b29528515e23598dce23f74284773a389f); [#285](https://github.com/agentjido/jido_ai/pull/285) | PR 285 names Igniter 0.7.9 to 0.8.0 and introduces ExAST 0.11.2. It also changes Decimal, Finch, Jason, Mint and Telemetry. Igniter notes cover three-element dependency declarations and CLI option values containing dots. Validate installation and warning-free compilation against the fresh dependency graph. Retain scoped CLI/config edits in a consumer fixture. | `RELEASE/installer-compatibility`, `RELEASE/dependency-runtime`, `RELEASE/runtime-matrix` |
| [a79ef18f](https://github.com/agentjido/jido_ai/commit/a79ef18f6aa8f50b1d65d0396646bd65d3957177); [#284](https://github.com/agentjido/jido_ai/pull/284) | PR 284 updates ExDoc 0.40.1 to 0.40.2 and makeup_erlang 1.0.3 to 1.1.0. Release notes cover HTML, Markdown, llms output and EPUB fixes. Required AI outputs remain HTML and Markdown; an upstream format is not automatically a new deliverable. Build the required documentation formats and check source links, extras and packaged examples. | `RELEASE/docs-formats`, `RELEASE/package-metadata` |
| [7c2fea19](https://github.com/agentjido/jido_ai/commit/7c2fea19d3d831f9ba2500d94484f7d112b139d2); no associated PR | This mixed commit updates Jido/Action requirements to 2.3, ReqLLM to 1.12 and Zoi to 0.18. The Agent test changes Jido.Identity.Plugin to Jido.Agent.Identity.Plugin. The release caller moves v4 to v5, grants actions write and replaces inherited secrets with HEX_API_KEY. Lock changes include Decimal 3, Zoi 0.18.4, time_zone_info replacing tzdata and libgraph resolving to multigraph. All changed lock entries are recorded in the structured ledger. Preserve default and overridden Plugin choices through v3 equivalents. Validate the shared release workflow contract and final dependency graph. Keep the explicit secret mapping in release preparation. | `HIST-17/plugin-choices`, `RELEASE/workflow-contract`, `RELEASE/dependency-runtime` |
| [ee2daf6a](https://github.com/agentjido/jido_ai/commit/ee2daf6ac6ed16ee0633a1f5716f91659e966e01); [#305](https://github.com/agentjido/jido_ai/pull/305) | PR 305 updates the ReqLLM requirement and lock to 1.14. Its explicit purpose is to validate the ReAct file-reference worker fix against the current release. The lock also changes Decimal, Igniter, Jason constraints, JSV, LLMDB, Mint, SSE and Texture. The reported fast suite and quality results are historical only. Retain file references through the real ReAct worker and provider request with the selected ReqLLM version. | `RELEASE/provider-contracts`, `HIST-03/live-file-request`, `RELEASE/dependency-runtime` |
| [bc6d570b](https://github.com/agentjido/jido_ai/commit/bc6d570b10766fb9ee117c9e2d8807d0988f4a70); [#320](https://github.com/agentjido/jido_ai/pull/320) | PR 320 names Igniter 0.8.1 to 0.8.2 and also updates ExAST, Finch, Req and Sourceror. Notes cover empty config lists, environment-scoped runtime config, stderr issue output, module remapping and upgrade/help handling. Keep installer config edits and CLI behavior correct in a fresh consumer; check actual resolved parser and transport packages. | `RELEASE/installer-compatibility`, `RELEASE/dependency-runtime` |
| [260a92f8](https://github.com/agentjido/jido_ai/commit/260a92f8303e08e527c4a9f44dcd9b94a608b688); [#321](https://github.com/agentjido/jido_ai/pull/321) | PR 321 updates ReqLLM 1.16 to 1.17 and introduces required Goth/JOSE, later made optional by 9ba39135. Notes cover reasoning summaries, Vertex ADC, trailing usage after finish, object capability detection, Ollama empty bodies and killed stream-consumer cleanup. ExAWS, ExAST, JSV, LLMDB and Texture also change. Keep provider error, usage, reasoning, object and tool behavior through the shared adapter. Test optional cloud authentication separately from the minimum consumer. | `RELEASE/provider-contracts`, `RELEASE/dependency-runtime` |
| [6e28e30e](https://github.com/agentjido/jido_ai/commit/6e28e30e6e96f832fb1d53c7238376de7caab4db); no associated PR | The lock moves Mint 1.9.0 to 1.9.1 and HPAX 1.0.3 to 1.0.4. No AI source changes or associated PR. Keep the selected HTTP stack compatible with streaming, timeout and cleanup behavior. | `RELEASE/http-stack`, `RELEASE/dependency-runtime` |
| [9ba39135](https://github.com/agentjido/jido_ai/commit/9ba391355d7b388254347d59596fc1c948e6e775); [#322](https://github.com/agentjido/jido_ai/pull/322) | PR 322 updates ReqLLM 1.17 to 1.17.1. Goth, JOSE and ExAWS leave the lock and authentication edges become optional. ExAST, JSV and LLMDB change. Notes cover tool-response content, leading argument fragments, wrapped transport retries, provider defaults and Ollama stream bodies. Retain optional cloud dependencies and provider content/error decoding without making every consumer install cloud authentication packages. | `RELEASE/provider-contracts`, `RELEASE/dependency-runtime` |
| [11d81abf](https://github.com/agentjido/jido_ai/commit/11d81abf483be3cc60f09e83b86f94be7353e3b1); no associated PR | The lock updates Earmark Parser 1.4.44 to 1.4.45, Erlex 0.2.8 to 0.2.9, Makeup 1.2.1 to 1.2.2 and Zoi 0.18.4 to 0.18.5. No production source change. Keep docs, type checks and schema behavior valid with the resolved package versions. | `RELEASE/docs-formats`, `RELEASE/current-type-checks`, `RELEASE/schema-error-compatibility` |
| [0f8f7e0d](https://github.com/agentjido/jido_ai/commit/0f8f7e0dcf98fc1453176effb200a4f25b0bce46); no associated PR | The lock updates ExAST 0.12.9 to 0.12.10, GitHooks 0.8.1 to 0.9.0, Recase 0.8.1 to 0.9.1, JSV 0.21.1 to 0.21.2, LLMDB 2026.7.0 to 2026.7.1 and Mint 1.9.1 to 1.9.2. Validate the complete consumer dependency graph, HTTP behavior and local tooling checks. | `RELEASE/dependency-runtime`, `RELEASE/http-stack`, `RELEASE/current-type-checks` |
| [a77053d4](https://github.com/agentjido/jido_ai/commit/a77053d44f53dd8f76b299b0eec38097e550d954); no associated PR | This commit moves Mint 1.9.2 to 1.9.3 and names CVE-2026-59249 in its message. Later source uses Mint 1.10. The commit is evidence of a maintenance requirement, not a claim that the future v3 graph is free of vulnerabilities. Retain a current dependency audit and HTTP acceptance checks; do not freeze a historical security-fix version. | `RELEASE/http-stack`, `RELEASE/dependency-runtime` |
| [039a7dd7](https://github.com/agentjido/jido_ai/commit/039a7dd746159fb39507f5cdf8c83912dc416e35); no associated PR | The lock updates Earmark Parser 1.4.45 to 1.4.46, LLMDB 2026.7.1 to 2026.7.2, Req 0.6.2 to 0.6.3 and Zoi 0.18.5 to 0.18.6. No production API change. Keep documentation, model metadata, HTTP and schema compatibility through fresh resolution. | `RELEASE/dependency-runtime`, `RELEASE/docs-formats`, `RELEASE/schema-error-compatibility` |
| [5fdb3323](https://github.com/agentjido/jido_ai/commit/5fdb3323fd9516425d518880a9a23ab64eea666f); [#330](https://github.com/agentjido/jido_ai/pull/330) | PR 330 updates ExAST 0.12.10 to 0.13.1, time_zone_info 0.7.14 to 0.7.15 and Zoi 0.18.6 to 0.18.7. Two maintainer comments first park the update for ExAST PR 14, then report validation after its release restored Elixir 1.18 metadata. The upstream PR body and all discussion were read as context. Prove the declared minimum Elixir version with a fresh dependency graph, including installer dependencies. A current-runtime result cannot close the minimum-runtime check. | `RELEASE/runtime-matrix`, `RELEASE/installer-compatibility`, `RELEASE/dependency-runtime` |
| [4abe4b41](https://github.com/agentjido/jido_ai/commit/4abe4b41c0eae2c4311ca29af57fc5eb959075e6); [#333](https://github.com/agentjido/jido_ai/pull/333) | PR 333 updates Igniter 0.8.2 to 0.8.3 and GlobEx 0.1.11 to 0.1.12. Relevant notes cover verbose option propagation, rm --check, declined install prompts, nested config and Elixir 1.20 warnings. New upstream Phoenix helpers are not new AI scope. Keep generated installer files and supported CLI/config edits correct on the declared runtimes. | `RELEASE/installer-compatibility`, `RELEASE/runtime-matrix` |
| [cc70641d](https://github.com/agentjido/jido_ai/commit/cc70641dfe1eaca9d1fdf167160d0ed50df0fa21); [#344](https://github.com/agentjido/jido_ai/pull/344) | PR 344 updates Action 2.3.1 to 2.3.2, Req 0.6.3 to 0.7.2, Spitfire 0.3.13 to 0.4.0 and Splode 0.3.1 to 0.3.2. Action changes optional Lua/Req ranges; Req removes its optional ezstd edge. The reported full tests and dependency checks are historical. Resolve compatible Action and Req versions for v3 and preserve common error behavior and warning-free tooling. | `RELEASE/dependency-runtime`, `RELEASE/http-stack`, `RELEASE/schema-error-compatibility` |
| [650303fb](https://github.com/agentjido/jido_ai/commit/650303fbf734a063b4d99a49d5037a68fcfe3b4e); [#345](https://github.com/agentjido/jido_ai/pull/345) | PR 345 updates ReqLLM 1.17.1 to 1.19.0, JSV 0.21.2 to 0.22.0, LLMDB 2026.7.2 to 2026.7.5, Mimic 2.3.0 to 2.3.1 and Texture 1.2.0 to 1.2.1. Its stated intent is dependency maintenance with no AI API change. Retain the supported ReqLLM provider contract and run quality checks with the complete resolved graph. | `RELEASE/provider-contracts`, `RELEASE/dependency-runtime` |
| [7da2579d](https://github.com/agentjido/jido_ai/commit/7da2579d32e5ad8e946c06890ac50a793867b0f7); no associated PR | The lock updates GitOps 2.10.0 to 2.12.0, Jido 2.3.2 to 2.3.3 and ReqLLM 1.19.0 to 1.20.0. GitOps adds Jason. No production source changes or associated PR. Keep provider and core compatibility and release preparation checks against the final dependency graph. | `RELEASE/provider-contracts`, `RELEASE/dependency-runtime`, `RELEASE/release-simulation` |
| [38fa3f62](https://github.com/agentjido/jido_ai/commit/38fa3f62dcecb2f08cf6ecd9437ff62df229f32c); [#346](https://github.com/agentjido/jido_ai/pull/346) | PR 346 updates GitOps 2.12.0 to 2.12.1. Its release note describes solo_pr package configuration. This is release tooling context, not an Agent DSL feature. Keep supported release configuration valid with the final GitOps version. | `RELEASE/release-simulation`, `RELEASE/dependency-automation` |
| [9438914d](https://github.com/agentjido/jido_ai/commit/9438914df5ac6a9d882762eb510564783d8b9a07); [#355](https://github.com/agentjido/jido_ai/pull/355) | PR 355 updates GitOps 2.12.1 to 2.12.2, LLMDB 2026.7.5 to 2026.8.4, Mimic 2.3.1 to 2.4.0, Req 0.7.2 to 0.7.3 and ReqLLM 1.20.0 to 1.21.0. The PR records dependency, compile and test validation. Validate provider behavior, model metadata, test tooling and release preparation with the final package graph. | `RELEASE/provider-contracts`, `RELEASE/dependency-runtime`, `RELEASE/release-simulation` |
| [3212e565](https://github.com/agentjido/jido_ai/commit/3212e56593da8ae5ba53d86b523d1bc50ff75de4); [#357](https://github.com/agentjido/jido_ai/pull/357) | PR 357 updates Req 0.7.3 to 0.7.4 and ReqLLM 1.21.0 to 1.21.1. Relevant notes cover Responses response.failed/error chunks, Anthropic thinking-token details, unknown schema input keys and Google model-specific thinking levels. These cases use the existing error, usage and output examples. Preserve terminal provider errors and normalized usage; verify schema and thinking options through the actual provider encoding. | `RELEASE/provider-contracts`, `RELEASE/http-stack`, `RELEASE/dependency-runtime` |

## Acceptance cases to add with the feature ports

Use the existing 18 example families and one mock LLM server. The cases below
are specifications, not passing tests. Preserve real ReqLLM encoding and
decoding. The mock supplies HTTP, SSE and required provider envelopes; it does
not replace the AI facade, reasoning Flow, tools or result handling.

| Case | Input and result to prove | Failure and ownership checks | Stage |
| --- | --- | --- | --- |
| `HIST-01/stream-headers` | Run the same gateway Agent with normal and SSE responses. Set a base header and a per-request override. Inspect the actual path, headers and body at the server. For the supported Finch hook API, prove the configured adapter runs before the per-request callback. Check direct and Agent entry points that retain HTTP options. | A later request receives no earlier private header. Test custom Finch selection, connection failure and callback failure. Keep runtime callbacks outside portable profiles; serialized authoring uses trusted references. Scope global adapter setup so concurrent tests cannot share it. | 2 and 4; catalog 01, 05, 13 |
| `RELEASE/provider-contracts` | Use provider-specific variants of existing text, tool, object, media and usage examples. Inspect the encoded options and the decoded result. Cover supported `parallel_tool_calls`, `store: false`, session IDs, reasoning controls and provider labels where the retained API exposes them. Check ordered properties, nullable output, tool errors, file references and continuation IDs. | Send fragmented tool arguments, terminal Responses errors, trailing usage, malformed arguments and empty transport bodies. Preserve error and cleanup rules, and do not count usage twice. An option assertion before the transport is insufficient. | 2, 4, 5; final check at 7 |
| `HIST-03/live-file-request` | Start the real worker with a referenced file, execute a tool round, and inspect the next model request for its file content and MIME. This strengthens the existing content/reference example. | A missing or unsupported reference produces the documented error. No raw binary enters tool JSON. Retain request identity and file ownership across worker execution and restore. | 2, 4 and 6; catalog 03, 06 |
| `HIST-17/plugin-choices` | Compile and run the default Agent and explicit Plugin configurations on v3. Check the intended identity, memory/history and ordinary route behavior. | Preserve supported opt-outs and overrides. Map removed internal module names to v3 owners; do not copy the old Strategy or Thread runtime to satisfy a module-name assertion. | 3 and 5; catalog 16 |
| `RELEASE/schema-error-compatibility` | Run existing nested/nullable tool and output schemas through the selected Zoi/JSV stack. Check metadata, accepted values and structured error projection. | Invalid nested values keep useful paths and error types. Exception inspection is bounded and warning-free. Upstream `pick`/`omit` or traversal helpers need no new AI public API. | 2; package check at 7 |
| `RELEASE/installer-compatibility` | Install the actual package in a fresh consumer on the supported runtime floor. Test repeated generation, explicit names, nested/environment config and supported option values containing dots. Use relevant three-element dependency fixtures. | Check declined prompts, stderr and exit codes, optional installer absence, and warning-free generated files. Test CLI environment loading with and without optional Dotenvy. Do not rely on a development dependency to make a consumer work. | 7; catalog 18 |
| `RELEASE/dependency-runtime` | Resolve the publishable dependency declarations in a fresh consumer. Test the final Jido/Action/Signal set and ReqLLM, including their optional dependency edges. Record the resolved versions and runtime. | A minimum consumer must not require unused cloud authentication packages. Test supported cloud authentication in a separate explicit fixture. Local path overrides and a stale lock cannot prove published compatibility. | Cutover and 7 |
| `RELEASE/http-stack` | Run normal and streamed requests, disconnect, timeout and cleanup checks with the selected Req/Finch/Mint/HPAX graph. Run a current dependency audit and record its result. | A historical CVE fix is not a permanent version pin or a current security result. Record unresolved audit findings at the package gate. | 4 and 7 |

Provider variants belong to the existing historical error, media, output and
usage cases. Select the exact current API and provider shape during that port.
Do not require all combinations of all models. At least one real transport case
must detect each retained provider regression, with direct/Agent parity where
the public contract promises it. Responses and Anthropic envelopes need their
actual decoders; the default Chat Completions response cannot stand in for them.

Reuse the release checks from [review 06](06-release-and-documentation.md):

- `RELEASE/runtime-matrix`: test the declared floor with fresh dependencies,
  including optional installation. The current-runtime foundation run does not
  close this check.
- `RELEASE/workflow-contract`: verify shared workflow v5 inputs, intended
  permissions and explicit `HEX_API_KEY` mapping. Use static checks and safe
  local simulation. Do not dispatch publication.
- `RELEASE/release-simulation` and `RELEASE/generated-notes`: verify configured
  managed files and multiline commit notes in a temporary checkout. Keep
  preparation separate from publication.
- `RELEASE/docs-formats`, `RELEASE/current-type-checks` and
  `RELEASE/dependency-automation`: validate the final package configuration.
  Do not add an Agent example for a docs formatter or a dependency bot label.

## Source anchors and limits

The baseline anchors are [package requirements](../../../mix.exs),
[resolved dependencies](../../../mix.lock),
[Agent options](../../../lib/jido_ai/authoring/agent.ex),
[request options](../../../lib/jido_ai/request.ex),
[ReAct execution](https://github.com/agentjido/jido_ai/blob/fc5bc1434ddb69493fe8a68443f03bc6a198c5a2/lib/jido_ai/reasoning/react/runner.ex),
[HTTP option tests](../../../test/jido_ai/react/runtime_runner_test.exs),
[Plugin tests](../../../test/jido_ai/agent_test.exs),
[installer tests](../../../test/jido_ai/install_task_test.exs),
[CLI environment loading](../../../lib/mix/tasks/jido_ai.ex), and the
[release caller](../../../.github/workflows/release.yml).

The final baseline has ReqLLM 1.21.1. The isolated foundation uses ReqLLM 1.22.
Record that distinction during cutover. Neither lockfile proves every retained
AI feature on v3. Keep all 126 port rows pending until the named tests or package
checks run against the migrated production package.
