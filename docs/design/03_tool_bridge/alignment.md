# 03 — Tool Bridge Alignment

> Seam alignment plan. This document and its design are pending approval.

## Status

- Design reviewed: 2026-09-09 for alignment only.
- Code reviewed: 17c97ca04d97b26a1c7017250c90053ad674f33f.
- Prerequisites: 00_boundary_invariants, 01_ai_values, and 02_model_gateway.
- Alignment state: Blocked.
- Blockers: design approval and the package compile failure.

Proven means that current source and a direct executable test assertion exist. It does not mean that the current package test suite passes.

## Inputs And Evidence

- Target design: design.md.
- Catalog and admission: lib/jido_ai/operations/tool_catalog.ex:6-86 and 213-260.
- Tool sources: lib/jido_ai/authoring/tool_source.ex.
- Result normalization: lib/jido_ai/tool_result.ex:7-139.
- Effects policy and applier: lib/jido_ai/effects/policy.ex and lib/jido_ai/effects/applier.ex.
- Tool execution: lib/jido_ai/operations/runtime.ex:798-846.
- Tool Flow lowering: lib/jido_ai/operations/runtime.ex:957-971.
- Adapter tests: test/jido_ai/tool_adapter_test.exs:256-328.
- V3 result tests: examples/v3/test/examples/02_requests/02_09_tool_results_test.exs:42-398.

## Retained Baseline

- Keep deterministic tool discovery, definition validation, and admission.
- Keep Jido Action as the executable tool form.
- Keep call-order preservation and stable tool call IDs.
- Keep normalized content and portability checks.
- Keep EffectsPolicy and the explicit effect applier.
- Keep tool execution inside the shared AI Flow.

## Gap Register

| Gap | Requirement | Current evidence | Difference | Disposition |
| --- | --- | --- | --- | --- |
| TLS-GAP-001 | TLS-REQ-003, TLS-REQ-005 | tool_catalog.ex | Discovery and validation exist, but collision and precedence rules are not proved for every source. | Add a source precedence table and collision tests. |
| TLS-GAP-002 | TLS-REQ-011 | current tool bridge | There is no formal prebuilt catalog snapshot contract. | Add a portable snapshot format or remove this option from the design. |
| TLS-GAP-003 | TLS-REQ-012, TLS-REQ-013, TLS-REQ-014 | shared/tool_result.ex | Normalization exists, but the public result and error taxonomy do not fully match the target contract. | Approve the value shape and add compatibility conversion. |
| TLS-GAP-004 | TLS-REQ-016, TLS-REQ-018 | runtime.ex:957-971 | Flow Map and Dispatch are present, but explicit positive max concurrency is not proved in the Flow declaration. | Make the bound explicit and test invalid values. |
| TLS-GAP-005 | TLS-REQ-020, TLS-REQ-021 | effects_policy.ex and effects_applier.ex | Effect handling exists, but idempotency and replay safety are not a complete contract. | Add effect IDs, deduplication ownership, and replay tests. |
| TLS-GAP-006 | TLS-REQ-022 | runtime.ex:846 | Retry delay uses Process.sleep inside the worker. | Move delay to a scheduler-visible retry boundary. |

## High-Level Work Sequence

This sequence defines outcomes and gates. Detailed implementation planning comes after design approval.

1. Approve tool source precedence, catalog snapshot, and public result values.
2. Complete catalog collision, reachability, and admission tests.
3. Make Flow concurrency and timeout limits explicit.
4. Normalize all adapter outputs and errors at one boundary.
5. Define effect idempotency and replay behavior.
6. Replace in-worker retry delay and run order, retry, effect, and portability tests.

## Acceptance Matrix

| Requirement | Current evidence | Required evidence | State |
| --- | --- | --- | --- |
| TLS-REQ-001 | ToolCatalog builds definitions | Passing deterministic catalog tests | Proven |
| TLS-REQ-002 | Action target validation | Passing Action identity tests | Proven |
| TLS-REQ-003 | several tool sources supported | Full precedence proof | Partial |
| TLS-REQ-004 | duplicate validation exists | Passing duplicate name tests | Proven |
| TLS-REQ-005 | admission and source validation | Full collision matrix | Partial |
| TLS-REQ-006 | schemas are derived | Passing schema tests | Proven |
| TLS-REQ-007 | unreachable tools rejected | Passing reachability tests | Proven |
| TLS-REQ-008 | admission policy exists | Passing deny and allow tests | Proven |
| TLS-REQ-009 | timeouts and retries validated | Passing finite-bound tests | Proven |
| TLS-REQ-010 | definitions are exported | Passing provider-definition tests | Proven |
| TLS-REQ-011 | no snapshot contract | Portable snapshot tests | Missing |
| TLS-REQ-012 | ToolResult normalizer exists | Approved public result value | Partial |
| TLS-REQ-013 | normalized content exists | Complete content compatibility tests | Partial |
| TLS-REQ-014 | error normalization exists | Stable tool error taxonomy | Partial |
| TLS-REQ-015 | order is preserved | Passing multi-call order tests | Proven |
| TLS-REQ-016 | IDs are retained | Full call and result correlation tests | Partial |
| TLS-REQ-017 | Flow Map and Dispatch exist | Passing shared Flow tests | Proven |
| TLS-REQ-018 | Map is present | Explicit positive max concurrency | Partial |
| TLS-REQ-019 | tool Actions use Jido.Exec | Passing execution ownership tests | Proven |
| TLS-REQ-020 | effects policy exists | Complete effect boundary tests | Partial |
| TLS-REQ-021 | no full idempotency contract | Effect replay and deduplication tests | Missing |
| TLS-REQ-022 | Process.sleep in retry loop | Scheduler-visible retry | Conflict |

## Migration And Compatibility

- Keep current Action-based tools and definition generation.
- Convert current ReqLLM tool results at the adapter edge.
- Accept current tool source forms through the approved precedence resolver.
- Do not persist live Action, process, task, or provider values in catalog snapshots.

## Assumptions And Blockers

- Jido Action and Jido.Exec remain the execution owners.
- The effect applier remains the only place that applies approved external effects.
- Package compile failure blocks the final integration tests.

## Completion Criteria

- Catalog construction is deterministic for every source and collision case.
- Tool execution has explicit concurrency, timeout, retry, and cancellation bounds.
- All public results and errors use approved portable values.
- Effect replay is idempotent, observable, and covered by tests.
