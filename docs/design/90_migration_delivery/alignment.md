# 90 — Migration And Delivery Alignment

> Seam alignment plan. This document and its design are pending approval.

## Status

- Design reviewed: 2026-09-09 for alignment only.
- Code reviewed: 17c97ca04d97b26a1c7017250c90053ad674f33f.
- Prerequisites: all seams 00 through 12.
- Alignment state: Blocked.
- Blockers: design approval, incomplete release artifacts, and release metadata conflicts.

Proven means that current source and a direct executable test assertion exist. It does not mean that the current package test suite passes.

## Inputs And Evidence

- Target design: design.md.
- Package metadata and dependencies: mix.exs:4-6 and mix.exs:56-67.
- Primary package documentation: README.md and guides.
- V3 examples and tests: examples and test/examples.
- Historical V3 spike documents: docs/v3-spike. They are intent only.
- Current design inventory: docs/design.
- Compile result: `mix compile --warnings-as-errors` passes with `Jido.Thread`
  and `Jido.Session` in the package root.
- Sibling integration state: jido is clean on v3-spike at c835ad5e2c08e97826e15158a5889955d551af2c with the new Plugin facet contract; jido_action and jido_signal are on release/v3.

## Retained Baseline

- Keep V3 examples as executable feature evidence.
- Keep Jido.AI.Agent as the canonical Spark authoring form.
- Keep current V3 sibling path dependencies for local integration work.
- Reject V2 state and checkpoint formats.
- Keep release gates strict: warnings as errors, dependency-order tests, documentation checks, and version checks.

## Gap Register

| Gap | Requirement | Current evidence | Difference | Disposition |
| --- | --- | --- | --- | --- |
| DEL-GAP-001 | DEL-REQ-001 through DEL-REQ-006 | current modules, examples, and docs | The removal inventory is not complete. | Complete the V2 removal inventory. |
| DEL-GAP-002 | DEL-REQ-007, DEL-REQ-008, DEL-REQ-011 | mix.exs:4-6 and path dependencies | The package version is 2.3.0, the description claims wrong ownership, and release dependency constraints are not ready. | Correct metadata and publish one compatible V3 version matrix. |
| DEL-GAP-003 | DEL-REQ-010, DEL-REQ-012, DEL-REQ-013, DEL-REQ-018 | compile and test state | Compilation passes, but the final release evidence index is incomplete. | Generate the final evidence ledger. |
| DEL-GAP-004 | DEL-REQ-019, DEL-REQ-020, DEL-REQ-024 | README.md and guides | Primary guides still lead with V2 and Strategy-era surfaces. | Rewrite migration and primary guides after designs are approved. |
| DEL-GAP-005 | DEL-REQ-005, DEL-REQ-026, DEL-REQ-027, DEL-REQ-028 | removals and examples | The final V2 removal inventory is incomplete. | Complete removal notes and prove obsolete code is absent. |
| DEL-GAP-006 | DEL-REQ-029, DEL-REQ-030, DEL-REQ-031 | current release process | There is no complete performance, security, or operational readiness gate. | Define budgets, threat checks, load tests, and rollback procedures. |
| DEL-GAP-007 | DEL-REQ-032 | current repositories | Local V3 branch alignment is known, but no clean final multi-package release rehearsal exists. | Run a clean dependency-order release rehearsal after all seam gates pass. |

## High-Level Work Sequence

This sequence defines outcomes and gates. Detailed implementation planning comes after design approval.

1. Approve all seam designs and freeze the intended V3 public contracts.
2. Build complete API, behavior, state, Signal, checkpoint, dependency, and removal inventories.
3. Resolve all upstream seam conflicts and the Jido.Thread compile blocker.
4. Remove compatibility adapters and complete guides and rejection tests.
5. Correct version, package description, and release dependencies.
6. Run compile, test, documentation, type, security, performance, and multi-package integration gates.
7. Produce the final requirement evidence ledger and release or no-release verdict.

## Acceptance Matrix

| Requirement | Current evidence | Required evidence | State |
| --- | --- | --- | --- |
| DEL-REQ-001 | partial API inventory in designs | Complete approved public API inventory | Partial |
| DEL-REQ-002 | V3 examples cover main behavior | Complete behavior parity matrix | Partial |
| DEL-REQ-003 | compatibility surfaces are being removed | Complete removal inventory | Partial |
| DEL-REQ-004 | no complete Signal inventory | V3 Signal inventory | Missing |
| DEL-REQ-005 | removal notes exist in parts | Full replacement and removal list | Partial |
| DEL-REQ-006 | no full dependency inventory | Approved owner and version matrix | Missing |
| DEL-REQ-007 | version is 2.3.0 and metadata is stale | Approved V3 version and metadata | Conflict |
| DEL-REQ-008 | local sibling branches are compatible | Passing release dependency matrix | Partial |
| DEL-REQ-009 | V3 sibling paths are selected | Passing V3 dependency tests | Partial |
| DEL-REQ-010 | no unified evidence ledger | One link per requirement to passing proof | Missing |
| DEL-REQ-011 | package description claims wrong ownership | Correct package ownership metadata | Conflict |
| DEL-REQ-012 | alignment matrices now exist | All requirements Proven | Missing |
| DEL-REQ-013 | warnings-as-errors compile passes | Final release run | Proven |
| DEL-REQ-014 | many focused tests exist | Complete package and integration test pass | Partial |
| DEL-REQ-015 | V3 examples are extensive | All examples compile and pass | Partial |
| DEL-REQ-016 | blocker policy is documented | Zero active release blockers | Proven |
| DEL-REQ-017 | V3 fixtures exist | Complete V3 fixtures | Partial |
| DEL-REQ-018 | no final release evidence report | Reproducible release gate report | Missing |
| DEL-REQ-019 | some migration material exists | One complete V2-to-V3 guide | Partial |
| DEL-REQ-020 | primary guides lead with old APIs | V3-first primary guides | Conflict |
| DEL-REQ-021 | V3 examples cover all seams | Passing seam example index | Partial |
| DEL-REQ-022 | current checkpoint tests exist | Complete current-format checkpoint set | Partial |
| DEL-REQ-023 | obsolete paths have been removed in parts | Full V2 removal inventory and source scan | Partial |
| DEL-REQ-024 | historical docs remain prominent | Historical-only labels and V3 canonical links | Conflict |
| DEL-REQ-025 | changelog inputs exist in history | Complete V3 release notes | Partial |
| DEL-REQ-026 | CLI uses public V3 APIs | Complete CLI matrix | Partial |
| DEL-REQ-027 | public test helpers exist | Complete helper matrix | Partial |
| DEL-REQ-028 | current test helpers exist | Complete V3-only helper matrix | Partial |
| DEL-REQ-029 | no approved performance budgets | Load and performance gate | Missing |
| DEL-REQ-030 | no complete security gate | Threat and secret-leak gate | Missing |
| DEL-REQ-031 | no operational readiness report | Runbook, rollback, and support gate | Missing |
| DEL-REQ-032 | local branch state is known | Clean multi-package release rehearsal | Partial |

## V3 migration policy

- Do not ship V2 source or data compatibility paths.
- Give each removed API a V3 replacement or an explicit no-replacement reason.
- Keep docs/v3-spike as historical input and label it as non-canonical.
- Restore Hex version constraints before release unless a different source is explicitly approved.
- Do not release with an unclean dependency matrix or an unproved requirement.

## Assumptions And Blockers

- Design approval is required before runtime implementation.
- The sibling jido worktree changed outside this task and is now clean at c835ad5e2c08e97826e15158a5889955d551af2c. This task did not change it.
- Any future compile failure is a release blocker.
- A row marked Proven still needs a successful final rerun in the clean release rehearsal.

## Completion Criteria

- Every DEL requirement and every requirement in seams 00 through 12 is Proven.
- All package metadata, dependencies, guides, migrations, and removals match the approved V3 contract.
- All compile, test, security, performance, documentation, and operational gates pass.
- A clean dependency-order rehearsal gives a release verdict of ready.
