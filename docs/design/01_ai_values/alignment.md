# 01 — AI Values Alignment

> Seam alignment plan. This document and its design are pending approval.

## Status

- Design reviewed: 2026-09-09 for alignment only.
- Code reviewed: 17c97ca04d97b26a1c7017250c90053ad674f33f.
- Prerequisites: 00_boundary_invariants.
- Alignment state: Blocked.
- Blockers: design approval and the package compile failure.

Proven means that current source and a direct executable test assertion exist. It does not mean that the current package test suite passes.

## Inputs And Evidence

- Target design: design.md.
- Values: lib/jido_ai/query.ex, context.ex, turn.ex, turn_content.ex, output.ex, usage.ex, and error.ex.
- Sanitization: lib/jido_ai/error/sanitize.ex:21-64.
- Query tests: test/jido_ai/query_test.exs:7-156.
- Turn tests: test/jido_ai/turn_test.exs:46-345.
- Output tests: test/jido_ai/output_test.exs:38-178.
- Usage tests: test/jido_ai/usage_test.exs:4-142.
- Error tests: test/jido_ai/error/model_test.exs and test/jido_ai/error/sanitize_test.exs:46-60.
- Historical input only: docs/v3-spike.

## Retained Baseline

- Keep Query file-reference checks and safe summaries.
- Keep Context entry ordering and message projection.
- Keep Turn normalization for text, object, tool call, tool result, usage, and incomplete responses.
- Keep Output validation with bounded repair data.
- Keep Usage normalization and merge behavior.
- Keep one normalization entry point for external failures.

## Gap Register

| Gap | Requirement | Current evidence | Difference | Disposition |
| --- | --- | --- | --- | --- |
| VAL-GAP-001 | VAL-REQ-001, VAL-REQ-002 | query.ex, context.ex, output.ex | Constructors do not use one stable tagged result contract. | Define and apply one constructor and validation result contract. |
| VAL-GAP-002 | VAL-REQ-009, VAL-REQ-014 | context.ex and turn.ex | Context and Turn are usable, but portable encoding is not versioned and proved for every form. | Add explicit codecs and round-trip tests. |
| VAL-GAP-003 | VAL-REQ-012 | turn.ex:586 | An older tool helper still uses Jido.Exec inside a value module. | Move execution behavior out of the value layer. |
| VAL-GAP-004 | VAL-REQ-019 | error.ex | Error has type and message fields, not the required stable category and code contract. | Add stable error categories and codes with compatibility mapping. |
| VAL-GAP-005 | VAL-REQ-020 | error_sanitize_test.exs:46-60 | The log projection test keeps api_key and secret text. | Redact secret values in all log projections and add regression tests. |
| VAL-GAP-006 | VAL-REQ-021, VAL-REQ-022 | current value modules | Versioned encoding and forward/backward compatibility rules are absent for several portable values. | Add codec versions, migration rules, and compatibility fixtures. |

## High-Level Work Sequence

This sequence defines outcomes and gates. Detailed implementation planning comes after design approval.

1. Approve the portable value set and stable error taxonomy.
2. Standardize constructor and validation results.
3. Remove execution work from value modules.
4. Add versioned codecs for Query, Context, Turn, Output, Usage, and Error.
5. Harden safe and log projections.
6. Run round-trip, malformed-input, ordering, and secret-redaction tests.

## Acceptance Matrix

| Requirement | Current evidence | Required evidence | State |
| --- | --- | --- | --- |
| VAL-REQ-001 | value constructors exist | One stable tagged result contract | Conflict |
| VAL-REQ-002 | validation exists per value | Uniform validation result tests | Partial |
| VAL-REQ-003 | structs use plain fields | Portability checks for every field | Partial |
| VAL-REQ-004 | Profile normalization and summaries | Cross-value safe projection tests | Partial |
| VAL-REQ-005 | query_test.exs | Passing query form tests | Proven |
| VAL-REQ-006 | query file validation | Passing file-reference safety tests | Proven |
| VAL-REQ-007 | query summaries | Passing secret-safe summary tests | Proven |
| VAL-REQ-008 | context.ex entry model | Passing ordered context tests | Proven |
| VAL-REQ-009 | context message projection | Versioned context codec | Partial |
| VAL-REQ-010 | turn response normalization | Direct response-shape tests | Proven |
| VAL-REQ-011 | turn classification | Passing classification tests | Proven |
| VAL-REQ-012 | turn helper uses Jido.Exec | Pure value-layer implementation | Conflict |
| VAL-REQ-013 | content normalization | Passing content-form tests | Proven |
| VAL-REQ-014 | turn export helpers | Versioned portable round trip | Partial |
| VAL-REQ-015 | output constructor and validation | Passing output tests | Proven |
| VAL-REQ-016 | bounded repair fields | Passing retry-bound tests | Proven |
| VAL-REQ-017 | usage normalize | Passing provider normalization tests | Proven |
| VAL-REQ-018 | usage merge | Passing merge tests | Proven |
| VAL-REQ-019 | error type model | Stable category and code tests | Conflict |
| VAL-REQ-020 | sanitize functions exist | Full secret-redaction proof | Conflict |
| VAL-REQ-021 | no common versioned codec | Versioned encoding for all portable values | Missing |
| VAL-REQ-022 | no compatibility matrix | Forward and backward compatibility fixtures | Missing |

## Migration And Compatibility

- Accept current Query, Context, Turn, Output, Usage, and Error inputs during a defined transition.
- Map old error types to approved categories and codes.
- Decode current unversioned payloads only through an explicit legacy path.
- Do not persist provider structs or execution state as portable values.

## Assumptions And Blockers

- The error taxonomy needs design approval before implementation.
- Existing tests can be retained as compatibility fixtures.
- Package compile failure blocks the final test gate.

## Completion Criteria

- All six public values use the approved constructor, validation, encoding, and sanitization contracts.
- All portable values pass versioned round-trip and compatibility tests.
- No secret value is present in a default safe, log, signal, checkpoint, or inspection projection.
- No value module owns execution behavior.
