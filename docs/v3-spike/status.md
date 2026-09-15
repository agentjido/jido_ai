# Jido AI V3 status — 2026-09-14

## Maturity assessment

The package has a working V3 implementation with broad automated checks.
It is ready for application integration and API review. It is not yet a
verified stable V3 release. This is an engineering assessment, not a release tag.

The main risk has moved from basic compilation to release verification and
operation with real providers. Passing deterministic tests does not establish
model answer quality, production capacity, or long-running reliability.

The branch is `v3-spike`; the package still declares version `2.3.0`.
The working tree includes the authoring tests and fixes after baseline commit
`c0e8d9c1`. These results do not describe that commit alone.
Current dependency declarations and lock entries select Jido `3.0.0-beta.1`,
Jido Action `3.0.0-beta.11`, and Jido Signal `3.0.0-beta.4` from Hex.
The latest full run passed on this Hex dependency set. The earlier authoring
and coverage runs below used sibling path dependencies.

## Verification record

| Check | Recorded result | Scope |
| --- | --- | --- |
| Current format and compile checks | Passed | `mix format --check-formatted` and `mix compile --warnings-as-errors` |
| Current full tests, including authoring and examples | 2,876 passed; 4 skipped; 1 excluded | Hex V3 beta dependencies; seed 0; warnings treated as errors; 131.5 seconds |
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

The current test log is `/tmp/jido-ai-status-full.log` on the verification host.
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
limit. The last nine added tests found no further confirmed product bug.
This does not mean the package has no other bugs.

## Explicit limits

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
