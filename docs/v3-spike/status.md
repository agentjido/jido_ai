# Jido AI V3 status — 2026-09-15

## Current simplification checkpoint

The runtime simplification and callable Profile migration are implemented.
`jido_ai` owns `Jido.Session`, `Jido.Thread`, and `Jido.Thread.Entry`; their
module names stay unchanged. The execution CLI and root strategy inspection
helpers are removed. Agent + DSL + Profile is the main authoring model.

Examples now use prompt-only callable input, host-bound Profiles, and public
Configuration/History inspection. Detailed callable method and deadline cases
stay in unit tests. Examples retain route, raw-tool, quota, transport, failure,
and cancellation proofs. New authoring checks cover callable Plugin Profiles
through core definitions, Builder, and Codec with a host Registry.

No new runtime defect was confirmed during this consumer migration. The
failures were obsolete API expectations and test transport configuration.
Provider options must be bound under each Profile ID, including nested calls.

The dated records below include historical results. Use the latest entry in
the verification table and [simplification report](simplification.md) for this
checkpoint. The old line-coverage percentage has not been measured again.

Commit `087afb8c` contains these repairs. The complete deterministic suite
passes. The package is ready for further API review and application integration,
but is not a verified stable V3 release.

## Maturity assessment

The package has a working V3 implementation with broad automated checks.
It is ready for application integration and API review. It is not yet a
verified stable V3 release. This is an engineering assessment, not a release tag.

The main risk has moved from basic compilation to release verification and
operation with real providers. Passing deterministic tests does not establish
model answer quality, production capacity, or long-running reliability.

The branch is `v3-spike`; the package still declares version `2.3.0`.
Commit `2210629c` contains the authoring tests, fixes, and Hex V3 beta dependency
update after baseline commit `c0e8d9c1`. The example refactor separates application
code from test fixtures, adds public lesson checks, and checks catalog integrity.
The earlier suite and coverage records below predate those changes.
Current dependency declarations and lock entries select Jido `3.0.0-beta.1`,
Jido Action `3.0.0-beta.11`, and Jido Signal `3.0.0-beta.4` from Hex.
ReqLLM now uses a GitHub dependency pinned to
`888fca022fea50785e2a54f7eabfcc47d289ae41`. It includes the numeric-string usage
fix from [ReqLLM #1009](https://github.com/agentjido/req_llm/pull/1009).
The focused HTTP/SSE regressions pass, and their skip tags have been removed.
The earlier authoring and coverage runs below used sibling path dependencies.

## Verification record

| Check | Recorded result | Scope |
| --- | --- | --- |
| Current API inventory reconciliation | 2,861 passed; 1 existing flaky exclusion; no skips | Full suite with authoring/examples and four inventory checks; seed 0; warnings as errors; 125.0 seconds; format, forced compile, and generator drift check passed |
| Profile-bound consumer migration (`087afb8c`) | 2,857 passed; 1 existing flaky exclusion; no skips | Full suite with authoring and examples; seed 0; warnings as errors; 126.8 seconds |
| Profile-bound example suite | 658 passed; no skips | Includes catalog checks and final context-forwarding cleanup; seed 0; warnings as errors; 81.3 seconds |
| Profile-bound format and forced compile | Passed | Format check and `mix compile --force --warnings-as-errors` |
| Full suite after example and test timing fixes | 2,894 passed; 1 flaky test excluded; no skips | Authoring and examples included; ReqLLM `888fca02`; seed 0; warnings as errors; 134.5 seconds |
| Refined example suite on ReqLLM pin `888fca02` | 679 passed; no skips | Seed 0; warnings as errors; 141.8 seconds; includes public lesson and catalog checks |
| Current format and compile checks | Passed | `mix format --check-formatted` and `mix compile --warnings-as-errors` |
| Full tests on ReqLLM GitHub pin `39cf3eb3`, including authoring and examples | 2,879 passed; 4 skipped; 1 excluded | Seed 0; warnings as errors; 121.3 seconds; numeric-string usage skips retained |
| Refreshed example suite | 664 passed; 4 skipped | Includes three catalog checks; Hex V3 beta dependencies; seed 0; warnings as errors |
| Refreshed example suite with skips enabled | 664 passed; 4 failed | All 668 cases ran; only numeric-string usage fails in ReqLLM 1.22.0 |
| Full tests before the three catalog checks, including authoring and examples | 2,876 passed; 4 skipped; 1 excluded | Hex V3 beta dependencies; seed 0; warnings treated as errors; 131.5 seconds |
| Full tests with authoring and examples, before the last nine authoring tests | 2,867 passed; 4 skipped; 1 excluded | Local sibling V3 dependencies; warnings treated as errors |
| Latest authoring-only run | 233 passed | Includes the last nine authoring tests; local sibling V3 dependencies |
| Full line coverage audit, before the last nine tests | 92.2% | Whole package; configured minimum 90%; 2,866 passed, 5 skipped, 1 excluded |

The coverage run has a different skip count because a fresh-VM checkpoint
check skips under coverage. Coverage is not a measure of supported API completeness.
The full test alias excludes flaky tests. Neither skipped nor excluded cases
count as passing evidence. Coverage was not rerun after the last nine tests or
the dependency change.

Reproduce the current full check from the package root:

```sh
mix format --check-formatted
mix compile --warnings-as-errors
mix test --include authoring --include example --warnings-as-errors --seed 0
```

The current full test log is `/tmp/jido-ai-api-inventory-full.log`.
The prior consumer logs are `/tmp/jido-ai-refinement-full.log` and
`/tmp/jido-ai-refinement-examples.log` on the verification host.
The result above is retained here because temporary logs are not release artifacts.

## What works

- AI Agent definitions through modules, maps, keyword attributes, Profile
  values, core Builder, source JSON, and core Agent JSON.
- Turn and session requests through AgentServer, with streaming, cancellation,
  steering, context, multiple profiles, and rejection of busy requests.
- Action and Flow tools, structured output and repair, request controls,
  model routing, error handling, and recovery.
- Reasoning methods, retrieval, planning, quota accounting, capability Plugins,
  skill activation, and checkpoint/resume examples. See the
  [example capability summary](../../examples/README.md#what-the-examples-can-do).

The dedicated [authoring suite](../../test/authoring/README.md) has seven
saved cases, eight construction paths, and 14 saved JSON documents. It checks
complete definitions and state, invalid declarations, Plugin composition,
output limits, public imports, and execution after transport to a separate BEAM.
The receiving BEAM compiles the same trusted source and supplies its own Registry.
This does not prove migration between source versions.

All nine [authoring findings](../../test/authoring/BUGS.md) have regression
tests for their resolved behavior. Fixes include caller-context propagation,
metadata and source normalization, and enforcement of the complete state-size
limit. The later callable Profile tests found no further confirmed product bug.
This does not mean the package has no other bugs.

The example refactor uses native AI Agent declarations, except where core Plugin
composition or direct standalone APIs are the lesson. Test observers, fault
injection, and process barriers now live in test support. New public checks run
the cleaned completion, tool-limit, skill, and standalone configuration lessons.
The catalog checks guide structure, links, IDs, test pairs, and skipped lessons.

Verification also corrected test defects: a steering check did not prove control
admission and queue insertion before releasing its model; runtime examples competed with
concurrent unit tests for short application budgets; and a Session idempotence
assertion compared separate clock readings. The fresh-VM launcher now loads
runtime and declared tool modules instead of every unrelated fixture.

## Explicit limits

- Hex ReqLLM 1.22.0 and the old Git pin do not include the numeric-string usage
  fix. Keep the updated pin until a release includes it. The example suite now
  runs those regressions without skips.
- Dynamic `tool_sources` are on hold. Native requests reject them before model
  work; they do not silently omit tools. The skill runtime is a separate feature.
- Rich model export is out of scope. Public export accepts model IDs and aliases;
  rich records get a structured validation error. Core Registry references are
  not a portable model export feature.
- Native AI execution requires AgentServer. Direct native `Agent.cmd` calls
  return a runtime validation error.
- The authoring corpus is bounded, not general property testing. It covers
  ReAct and chain of thought; other reasoning methods have separate tests.
- The examples use a local HTTP/SSE provider. They do not prove real-provider
  compatibility, load capacity, durable distributed execution, or answer quality.

## Before a stable V3 release

1. Select the AI release version and verify a fresh consumer against the released
   dependency set, without sibling checkouts.
2. Run and record the release quality checks, package build, documentation build,
   supported runtime matrix, and disposition of skipped and flaky tests.
3. Reconcile the API map and 126-row history ledger with current test paths and
   results. Earlier source review is not completed migration acceptance.
4. Complete the migration guide and review remaining standalone skill
   continuation and reasoning inspection requirements from the historical plan.
5. Verify real-provider behavior and application-specific reliability, capacity,
   timeout, and recovery requirements before production use.

The immediate authoring scope is implemented and tested. These release checks
are not requests to add the deferred dynamic tool-source or rich-export features.

## Earlier records

The [root checkpoint](root-package-checkpoint.md) and
[implementation record](implementation.md) retain the September 7 migration
history. Their failure counts and references to a separate acceptance project
are historical. This page is the current summary.
