# History review 06: release, CI and documentation

Reviewed on 2026-09-06 against `fc5bc1434ddb69493fe8a68443f03bc6a198c5a2`.
This pass completes fourteen more source reviews. The total is 62 of 126.
All v3 port checks remain pending. No build, test, release or workflow ran.

The review read all fourteen complete diffs, their associated PR descriptions
and discussions, and the final local workflow and Mix configuration. Most of
these direct commits have no associated merged PR. This pass reviews Jido AI's
workflow callers; it does not claim a complete review of the external shared
workflow implementation. Dependency and later runtime changes remain separate
source-review work.

## Commit dispositions

| Commit | Final requirement to retain | Required package checks |
| --- | --- | --- |
| `3c734e1d` | The 2.1.0 release changes version and generated history only. Link the underlying feature commits to behavior cases. | RELEASE/version-contract, RELEASE/generated-notes |
| `47cb324c` / PR 251 | Shared workflows use a named compatibility channel instead of the moving main branch. Later changes select v5. | RELEASE/workflow-contract |
| `9dff9ee8` / PR 274 | Preserve merge-queue coverage, quality commands, advisory review and separate release preparation/publication paths. | RELEASE/workflow-contract, RELEASE/release-simulation |
| `0a1da261` | Keep weekly Mix dependency checks, scoped dependency commit messages and the configured PR bound. | RELEASE/dependency-automation |
| `6bf657c5` | Generate both HTML and Markdown documentation. Preserve the useful developer docs command. | RELEASE/docs-formats |
| `38b50460` / PR 293 | The rc5 change tests future compiler compatibility; it does not raise the supported stable floor. | RELEASE/runtime-matrix |
| `1185be67` | The rc6 change supersedes rc5 in the experimental compile lane. | RELEASE/runtime-matrix |
| `f1a6aec4` | Retain package/docs/CI/license links and the current Jido website, ecosystem and community destinations. | RELEASE/package-metadata |
| `fcb44557` | Retain the standardized project notice in both license files and the package license declaration. | RELEASE/package-metadata |
| `c316b3fd` | The 2.2.0 release changes version and generated history only. It does not close unreviewed feature commits. | RELEASE/version-contract, RELEASE/generated-notes |
| `3c78f6db` / PR 301 | CI and advisory review move to v5. Later runtime work also moves the release caller. | RELEASE/workflow-contract |
| `ebb79f9a` | Shared defaults temporarily replace explicit runtime inputs. Later explicit inputs define the target's matrix. | RELEASE/runtime-matrix, RELEASE/workflow-contract |
| `0f5368b3` | Release notes come from Git history. Keep behavior/API migration guidance separate and use clear Conventional Commits. | RELEASE/generated-notes |
| `2f83b922` | The 2.3.0 release changes version and generated history only. Keep all source changes after that release in scope too. | RELEASE/version-contract, RELEASE/generated-notes |

## Package acceptance replaces artificial Agent examples

These commits mostly change delivery behavior. They need package checks,
not an Agent that pretends to test a workflow. Preserve the feature examples
linked to the source commits listed in each release. Keep these release rows
pending until their named package checks pass against the actual v3 package.

| Check | Required evidence |
| --- | --- |
| `RELEASE/workflow-contract` | Parse/lint the final workflow callers. Resolve and record the shared workflow revision and supported input contract. Retain PR, merge-group and main-push CI coverage, concurrency cancellation and the intended permissions. Check that format, warning-free compile, Credo, docs, type checks and tests actually run. Preserve advisory review without treating it as a substitute for required tests. |
| `RELEASE/runtime-matrix` | Test the supported floor and current runtime against the v3 dependency set. The target declares Elixir `~> 1.18`; its CI pairs are OTP 27/Elixir 1.18, OTP 28/Elixir 1.18, OTP 28/Elixir 1.19 and OTP 29/Elixir 1.20. Compile-only experimental history is not passing test evidence. Record any deliberate change to support before changing the declaration. |
| `RELEASE/release-simulation` | Validate the version, package contents, tag/version inputs and preparation/publication split without publishing or pushing. A local package build and safe simulation must use the final dependency declarations. Distinguish full `dry_run` from `hex_dry_run`, which permits other release writes. Do not dispatch a publishing workflow as a validation step. |
| `RELEASE/dependency-automation` | Keep valid root Mix dependency update configuration: weekly schedule, ten open PR limit, dependency/Elixir labels and scoped `deps` messages. Verify that the publishable root package no longer depends on workspace-only paths. The acceptance project's local overrides remain separate. |
| `RELEASE/docs-formats` | Build HTML and Markdown from the actual package configuration. Both outputs contain the Agent DSL, direct APIs, migration guide and working examples. Check source links, extras and unresolved references. Use a command that does not open a browser in CI. A successful HTML-only build does not close the Markdown requirement. |
| `RELEASE/package-metadata` | Build and inspect the package archive. Verify required guides, usage rules, license and any runtime resources. Check the standardized notice and license declaration without changing their meaning. Align package metadata and README destinations. Verify public examples in a fresh consumer, using the unified mock for model work. |
| `RELEASE/version-contract` | The final package version, dependency ranges, documentation source reference and intended release tag agree. Preserve the old release history. Do not treat a version bump as implementation or acceptance evidence. Select the v3 release version at the release preparation stage. |
| `RELEASE/generated-notes` | Use source history and clear commit messages for generated notes. Keep the migration guide explicit about changed public APIs, state conversion and rollback. Cross-check release summaries against the full ledger; duplicate or omitted changelog bullets cannot change the source-review scope. |

The current root `test` alias excludes `flaky`. The smoke alias selects
`stable_smoke`. Preserve a useful default and smoke suite, then add an explicit
required run for the new integration cases. Neither the default alias nor a
green smoke run can close excluded integration requirements. Keep missing DSL
tests visibly pending until the real implementation passes.

## Final behavior and source limits

[PR 274](https://github.com/agentjido/jido_ai/pull/274) retains the package's
Credo threshold and records a broad local validation pass. Its author left
Dialyzer to CI. Those old results describe that rollout; they do not establish
that the current v3 package passes the same checks.

[PR 293](https://github.com/agentjido/jido_ai/pull/293) explicitly keeps stable
tests on Elixir 1.18 and 1.19 while adding the experimental compiler. The
later runtime change `e2b2d275` establishes the target's explicit four-pair
matrix and quality/release runtime. That commit still needs its own full
source review. Do not restore obsolete release-candidate lanes or rely on
unknown shared defaults merely because an earlier commit used them.

[PR 301](https://github.com/agentjido/jido_ai/pull/301) describes the v5 shared
workflow channel. Its actual AI diff changes CI and review only. The final
release file also uses v5 because of later work. Trace the final files instead
of applying the PR's broad wording to every file at that point in history.

The final Mix project still lists both HTML and Markdown formatters. Its
developer `docs` alias includes `--open`; the CI command specifies HTML only.
The package gate must prove both intended artifacts without assuming that
the current CI command already does so.

The final README uses `jido.run` destinations. The package links in `mix.exs`
still contain older `agentjido.xyz` destinations. Record this source mismatch
and make the metadata consistent during package migration. This review did
not check external redirect behavior.

The package manifest includes `LICENSE.md`, while the README license badge
links to repository `LICENSE`. Both files carry the same standardized notice.
Verify the shipped artifact and repository reference. This is a preservation
check, not a proposed license change.

The generated 2.1.0 notes have duplicate entries. The 2.2.0 notes omit some
changes present in the Git range, including the structured-output addition.
The target also has work after 2.3.0. This confirms why the audit uses all
reachable commits after the initial release, not only changelog bullets or
release tags.

Source evidence: [CI](../../../.github/workflows/ci.yml),
[release caller](../../../.github/workflows/release.yml),
[advisory review](../../../.github/workflows/review.yml),
[dependency updates](../../../.github/dependabot.yml),
[Mix configuration](../../../mix.exs), [README](../../../README.md),
[license](../../../LICENSE), [packaged license](../../../LICENSE.md),
[release history](../../../CHANGELOG.md), and
[repository guidance](../../../AGENTS.md).

At the final simplification pass, remove duplicate checks only when the
remaining command proves the same package behavior. Keep both documentation
formats, supported runtime tests, the fresh-consumer example and the complete
required integration run visible in the release evidence.
