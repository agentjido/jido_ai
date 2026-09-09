# 90 — Migration And Delivery Alignment

> Seam alignment plan. This document and its design are pending approval.

## Status

- Design reviewed: 2026-09-09 for alignment only.
- Code reviewed: 17c97ca04d97b26a1c7017250c90053ad674f33f.
- Prerequisites: all seams 00 through 12.
- Alignment state: Blocked.
- Blockers: design approval, compile failure, incomplete migration artifacts, and release metadata conflicts.

Proven means that current source and a direct executable test assertion exist. It does not mean that the current package test suite passes.

## Inputs And Evidence

- Target design: design.md.
- Package metadata and dependencies: mix.exs:4-6 and mix.exs:56-67.
- Primary package documentation: README.md and guides.
- V3 examples and tests: examples/v3/test/examples.
- Historical V3 spike documents: docs/v3-spike. They are intent only.
- Current design inventory: docs/design.
- Compile result: mix compile --warnings-as-errors fails in lib/jido_ai/session/context_operations.ex because Jido.Thread and Jido.Thread.Entry are unavailable.
- Sibling integration state: jido is clean on v3-spike at c835ad5e2c08e97826e15158a5889955d551af2c with the new Plugin facet contract; jido_action and jido_signal are on release/v3.

## Retained Baseline

- Keep V3 examples as executable compatibility and migration evidence.
- Keep Jido.AI.Agent only as a documented compatibility wrapper.
- Keep current V3 sibling path dependencies for local integration work.
- Keep current checkpoint migration fixtures as inputs to the full migration suite.
- Keep release gates strict: warnings as errors, dependency-order tests, documentation checks, and version checks.

## Gap Register

| Gap | Requirement | Current evidence | Difference | Disposition |
| --- | --- | --- | --- | --- |
| DEL-GAP-001 | DEL-REQ-001 through DEL-REQ-006 | current modules, examples, and docs | Inventories and examples exist, but there is no complete disposition, compatibility budget, removal schedule, or machine-checked migration matrix. | Create the approved API, behavior, state, Signal, checkpoint, and dependency inventories. |
| DEL-GAP-002 | DEL-REQ-007, DEL-REQ-008, DEL-REQ-011 | mix.exs:4-6 and path dependencies | The package version is 2.3.0, the description claims wrong ownership, and release dependency constraints are not ready. | Correct metadata and publish one compatible V3 version matrix. |
| DEL-GAP-003 | DEL-REQ-010, DEL-REQ-012, DEL-REQ-013, DEL-REQ-018 | compile and test state | There is no complete requirement evidence index, and the package does not compile with warnings as errors. | Fix prerequisite seams and generate the final evidence ledger. |
| DEL-GAP-004 | DEL-REQ-019, DEL-REQ-020, DEL-REQ-024 | README.md and guides | Primary guides still lead with V2 and Strategy-era surfaces. | Rewrite migration and primary guides after designs are approved. |
| DEL-GAP-005 | DEL-REQ-005, DEL-REQ-026, DEL-REQ-027, DEL-REQ-028 | deprecations and examples | Deprecation metadata, removal dates, and compatibility rejection cases are incomplete. | Add explicit since, replacement, warning, and removal data. |
| DEL-GAP-006 | DEL-REQ-029, DEL-REQ-030, DEL-REQ-031 | current release process | There is no complete performance, security, or operational readiness gate. | Define budgets, threat checks, load tests, and rollback procedures. |
| DEL-GAP-007 | DEL-REQ-032 | current repositories | Local V3 branch alignment is known, but no clean final multi-package release rehearsal exists. | Run a clean dependency-order release rehearsal after all seam gates pass. |

## High-Level Work Sequence

This sequence defines outcomes and gates. Detailed implementation planning comes after design approval.

1. Approve all seam designs and freeze the intended V3 public contracts.
2. Build complete API, behavior, state, Signal, checkpoint, dependency, and deprecation inventories.
3. Resolve all upstream seam conflicts and the Jido.Thread compile blocker.
4. Complete compatibility adapters, migrations, guides, and rejection tests.
5. Correct version, package description, and release dependencies.
6. Run compile, test, documentation, type, security, performance, and multi-package integration gates.
7. Produce the final requirement evidence ledger and release or no-release verdict.

## Acceptance Matrix

| Requirement | Current evidence | Required evidence | State |
| --- | --- | --- | --- |
| DEL-REQ-001 | partial API inventory in designs | Complete approved public API inventory | Partial |
| DEL-REQ-002 | V3 examples cover main behavior | Complete behavior parity matrix | Partial |
| DEL-REQ-003 | state shapes are documented in parts | Versioned state inventory | Partial |
| DEL-REQ-004 | no complete Signal inventory | Versioned Signal compatibility matrix | Missing |
| DEL-REQ-005 | some deprecations exist | Full deprecation and removal schedule | Partial |
| DEL-REQ-006 | no full dependency inventory | Approved owner and version matrix | Missing |
| DEL-REQ-007 | version is 2.3.0 and metadata is stale | Approved V3 version and metadata | Conflict |
| DEL-REQ-008 | local sibling branches are compatible | Passing release dependency matrix | Partial |
| DEL-REQ-009 | compatibility wrapper exists | Passing retained API compatibility tests | Partial |
| DEL-REQ-010 | no unified evidence ledger | One link per requirement to passing proof | Missing |
| DEL-REQ-011 | package description claims wrong ownership | Correct package ownership metadata | Conflict |
| DEL-REQ-012 | alignment matrices now exist | All requirements Proven | Missing |
| DEL-REQ-013 | compile fails | Clean warnings-as-errors compile | Conflict |
| DEL-REQ-014 | many focused tests exist | Complete package and integration test pass | Partial |
| DEL-REQ-015 | V3 examples are extensive | All examples compile and pass | Partial |
| DEL-REQ-016 | blocker policy is documented | Zero active release blockers | Proven |
| DEL-REQ-017 | some migration fixtures exist | Complete forward and backward fixtures | Partial |
| DEL-REQ-018 | no final release evidence report | Reproducible release gate report | Missing |
| DEL-REQ-019 | some migration material exists | One complete V2-to-V3 guide | Partial |
| DEL-REQ-020 | primary guides lead with old APIs | V3-first primary guides | Conflict |
| DEL-REQ-021 | V3 examples cover all seams | Passing seam example index | Partial |
| DEL-REQ-022 | checkpoint migration tests exist | Complete checkpoint migration set | Partial |
| DEL-REQ-023 | compatibility tests exist in parts | Full adapter and rejection matrix | Partial |
| DEL-REQ-024 | historical docs remain prominent | Historical-only labels and V3 canonical links | Conflict |
| DEL-REQ-025 | changelog inputs exist in history | Complete V3 release notes | Partial |
| DEL-REQ-026 | deprecated APIs lack full metadata | Since, replacement, and removal data | Conflict |
| DEL-REQ-027 | some warnings exist | Passing deprecation warning tests | Partial |
| DEL-REQ-028 | rejection tests exist in parts | Complete unsafe legacy behavior tests | Partial |
| DEL-REQ-029 | no approved performance budgets | Load and performance gate | Missing |
| DEL-REQ-030 | no complete security gate | Threat and secret-leak gate | Missing |
| DEL-REQ-031 | no operational readiness report | Runbook, rollback, and support gate | Missing |
| DEL-REQ-032 | local branch state is known | Clean multi-package release rehearsal | Partial |

## Migration And Compatibility

- Keep only compatibility paths that delegate to the approved V3 implementation.
- Give every deprecated API a documented replacement, warning, and removal release.
- Keep docs/v3-spike as historical input and label it as non-canonical.
- Restore Hex version constraints before release unless a different source is explicitly approved.
- Do not release with an unclean dependency matrix or an unproved requirement.

## Assumptions And Blockers

- Design approval is required before primary guide rewrites and runtime implementation.
- The sibling jido worktree changed outside this task and is now clean at c835ad5e2c08e97826e15158a5889955d551af2c. This task did not change it.
- The current package compile failure is a release blocker.
- A row marked Proven still needs a successful final rerun in the clean release rehearsal.

## Completion Criteria

- Every DEL requirement and every requirement in seams 00 through 12 is Proven.
- All package metadata, dependencies, guides, migrations, and deprecations match the approved V3 contract.
- All compile, test, security, performance, documentation, and operational gates pass.
- A clean dependency-order rehearsal gives a release verdict of ready.
