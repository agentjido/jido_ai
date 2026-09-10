# 02 — Model Gateway Alignment

> Seam alignment plan. This document and its design are pending approval.

## Status

- Design reviewed: 2026-09-09 for alignment only.
- Code reviewed: 17c97ca04d97b26a1c7017250c90053ad674f33f.
- Prerequisites: 00_boundary_invariants and 01_ai_values.
- Alignment state: Blocked.
- Blockers: design approval and the package compile failure.

Proven means that current source and a direct executable test assertion exist. It does not mean that the current package test suite passes.

## Inputs And Evidence

- Target design: design.md.
- Model resolution and direct helpers: lib/jido_ai/models.ex:87-268.
- Alias registry: lib/jido_ai/model_aliases.ex.
- Routing: lib/jido_ai/operations/model_router.ex.
- Request transformation: lib/jido_ai/operations/request_transform.ex.
- Execution and repair: lib/jido_ai/operations/runtime.ex:324-405 and lib/jido_ai/operations/runtime.ex:733-766.
- Helper behavior tests: examples/v3/test/examples/01_authoring/01_08_model_helpers_test.exs:45-128.
- Transform tests: examples/v3/test/examples/02_requests/02_05_request_transform_test.exs:94-109 and 224-239.
- Stream, incomplete, and setup tests: examples/v3/test/examples/02_requests/02_24_stream_usage_test.exs, examples/v3/test/examples/02_requests/02_25_incomplete_response_test.exs, and examples/v3/test/examples/02_requests/02_26_request_setup_test.exs:28-128.

## Retained Baseline

- Keep model aliases and tuple-based routing inputs during migration.
- Keep one model call ID for call, stream, usage, and completion events.
- Keep request transform validation before the provider call.
- Keep bounded structured-output repair.
- Keep incomplete response normalization and usage aggregation.

## Gap Register

| Gap | Requirement | Current evidence | Difference | Disposition |
| --- | --- | --- | --- | --- |
| MDL-GAP-001 | MDL-REQ-004, MDL-REQ-005 | models.ex:87-133 | Resolution accepts provider structs and maps. The selected reference is not one portable provider-neutral value. | Add an approved ModelRef and convert provider values only at the adapter edge. |
| MDL-GAP-002 | MDL-REQ-002, MDL-REQ-013, MDL-REQ-020 | model_router.ex and runtime events | Selection exists, but full reason metadata and resolved identity are not uniform on every path. | Define one selection result and event projection. |
| MDL-GAP-003 | MDL-REQ-007, MDL-REQ-008 | request_transform.ex | There is one transform stage, but it can receive runtime-rich request data. | Define named portable stages and restrict callback inputs and outputs. |
| MDL-GAP-004 | MDL-REQ-016, MDL-REQ-017, MDL-REQ-021 | models.ex:191-268 and 01_08_model_helpers_test.exs | Direct public helpers return ReqLLM response and stream values, and raw provider errors can cross the await boundary. | Normalize all public results through Jido.AI values. |
| MDL-GAP-005 | MDL-REQ-014, MDL-REQ-019 | runtime.ex:733-766 | Repair is bounded, but retry class and retry event data are not one gateway contract. | Add stable retry classification and attempt events. |
| MDL-GAP-006 | MDL-REQ-022 | current runtime | No separate retry worker exists, but this invariant is not protected by a direct test. | Add an execution ownership test. |

## High-Level Work Sequence

This sequence defines outcomes and gates. Detailed implementation planning comes after design approval.

1. Approve ModelRef, selection result, and gateway result values.
2. Add provider-edge conversion and reject provider structs at portable boundaries.
3. Define the ordered transform pipeline and portable callback contract.
4. Route direct helpers through the same normalization path as execution.
5. Standardize retry classes, retry events, and terminal errors.
6. Run helper, stream, object, transform, setup, and incomplete-response tests.

## Acceptance Matrix

| Requirement | Current evidence | Required evidence | State |
| --- | --- | --- | --- |
| MDL-REQ-001 | model router exists | One public selection contract | Proven |
| MDL-REQ-002 | route choice exists | Uniform reason metadata | Partial |
| MDL-REQ-003 | aliases resolve | Passing alias resolution tests | Proven |
| MDL-REQ-004 | provider structs accepted | Provider-neutral ModelRef only | Conflict |
| MDL-REQ-005 | aliases and tuples supported | Stable resolved identity | Partial |
| MDL-REQ-006 | session strips runtime fields | Full trust-boundary tests | Partial |
| MDL-REQ-007 | request transform exists | Named ordered stage pipeline | Partial |
| MDL-REQ-008 | callback gets rich request | Portable callback data only | Conflict |
| MDL-REQ-009 | failure blocks provider call | Passing pre-call failure test | Proven |
| MDL-REQ-010 | runtime creates call ID first | Passing correlation test | Proven |
| MDL-REQ-011 | model Action uses Jido.Exec | Passing execution ownership test | Proven |
| MDL-REQ-012 | response normalization exists | Passing normalized run tests | Proven |
| MDL-REQ-013 | model metadata is emitted | Uniform identity and reason schema | Partial |
| MDL-REQ-014 | bounded repair loop exists | Stable retry class and event tests | Partial |
| MDL-REQ-015 | repair stops at limit | Passing bounded repair tests | Proven |
| MDL-REQ-016 | helpers return ReqLLM values | Jido.AI value results on every public path | Conflict |
| MDL-REQ-017 | direct stream is ReqLLM stream | Provider-neutral public stream | Conflict |
| MDL-REQ-018 | usage normalization exists | Passing stream and non-stream usage tests | Proven |
| MDL-REQ-019 | incomplete responses normalize | Complete terminal and retry tests | Proven |
| MDL-REQ-020 | model events exist | Complete approved event metadata | Partial |
| MDL-REQ-021 | raw provider errors can escape | Stable public error normalization | Conflict |
| MDL-REQ-022 | no gateway retry worker found | Direct no-private-worker test | Partial |

## Migration And Compatibility

- Accept aliases, strings, and current tuples as ModelRef inputs for one migration period.
- Deprecate public return of ReqLLM.Response, ReqLLM.Stream, and provider errors.
- Keep ReqLLM values inside the provider adapter.
- Keep current callback names through a wrapper that passes only approved portable data.

## Assumptions And Blockers

- ReqLLM remains the provider adapter but is not a public value owner.
- Model routing policy remains in jido_ai.
- Package compile failure blocks the full acceptance run.

## Completion Criteria

- All public model calls return Jido.AI values.
- All portable model references and event data are provider-neutral.
- Transform stages are ordered, named, validated, and limited to portable data.
- Retry behavior is bounded, classified, observable, and executed through the approved runtime.
