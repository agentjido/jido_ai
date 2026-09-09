# 09 — Skills And Resources Alignment

> Seam alignment plan. This document and its design are pending approval.

## Status

- Design reviewed: 2026-09-09 for alignment only.
- Code reviewed: 17c97ca04d97b26a1c7017250c90053ad674f33f.
- Prerequisites: seams 00, 01, 07, and 08.
- Alignment state: Blocked.
- Blockers: design approval, package compile failure, and the global lazy registry conflict.

Proven means that current source and a direct executable test assertion exist. It does not mean that the current package test suite passes.

## Inputs And Evidence

- Target design: design.md.
- Skill specification and runtime validation: lib/jido_ai/skill/spec.ex.
- Resource policy: lib/jido_ai/skill/resource_policy.ex:11-42.
- Resource provider forms: lib/jido_ai/skill/resource_provider.ex:81-96.
- Skill activation and loading: lib/jido_ai/skill.
- Registry: lib/jido_ai/skill/registry.ex.
- Unit tests: test/jido_ai/skills.
- V3 skill tests: examples/v3/test/examples/18_skills/18_01_skill_runtime_test.exs:54-504.

## Retained Baseline

- Keep portable skill specifications and strict runtime validation.
- Keep resource roots, file counts, byte sizes, and traversal limits.
- Keep deterministic activation order and request-scoped resolved resources.
- Keep explicit provider forms for trusted runtime configuration.
- Keep checkpoint restore by stable skill and resource references.
- Keep failures normalized and sanitized.

## Gap Register

| Gap | Requirement | Current evidence | Difference | Disposition |
| --- | --- | --- | --- | --- |
| SKL-GAP-001 | SKL-REQ-004, SKL-REQ-005 | skill specification and activation code | Skill identity and version exist, but dependency and collision proof is not complete for every contribution. | Add a deterministic dependency graph and collision matrix. |
| SKL-GAP-002 | SKL-REQ-010 | resource provider and loader | Resource loading is bounded, but full content type and normalization behavior is not one public contract. | Define portable resource content and metadata values. |
| SKL-GAP-003 | SKL-REQ-015 | skill contributions | Action contributions exist, but plugin contribution collision validation depends on incomplete capability and Plugin contracts. | Complete seams 06 and 08 first. |
| SKL-GAP-004 | SKL-REQ-016, SKL-REQ-024 | skill/registry.ex | The global registry can start lazily during lookup. This creates an implicit process owner and fallback catalog. | Require an explicit host or session registry and remove lazy global start. |
| SKL-GAP-005 | SKL-REQ-025 | retained activation data | Stable identities and references are stored, but there is no approved versioned checkpoint schema. | Add versioned activation and resource reference codecs. |
| SKL-GAP-006 | SKL-REQ-026 | current examples | Compatibility is broad, but migration fixtures for registry ownership and checkpoint forms are incomplete. | Add legacy decode and re-resolution fixtures. |

## High-Level Work Sequence

This sequence defines outcomes and gates. Detailed implementation planning comes after design approval.

1. Approve SkillSpec, dependency, contribution, resource content, and registry ownership contracts.
2. Remove lazy global registry ownership.
3. Complete deterministic dependency, collision, and activation tests.
4. Standardize bounded resource loading and safe projections.
5. Add versioned activation checkpoint data and restore re-resolution.
6. Run unit and V3 skill tests after the package compiles.

## Acceptance Matrix

| Requirement | Current evidence | Required evidence | State |
| --- | --- | --- | --- |
| SKL-REQ-001 | SkillSpec exists | Passing constructor tests | Proven |
| SKL-REQ-002 | runtime validation exists | Passing malformed spec tests | Proven |
| SKL-REQ-003 | stable IDs and versions exist | Passing identity tests | Proven |
| SKL-REQ-004 | dependency data exists | Complete graph validation | Partial |
| SKL-REQ-005 | collision checks exist in parts | Full contribution collision matrix | Partial |
| SKL-REQ-006 | activation is ordered | Passing deterministic order tests | Proven |
| SKL-REQ-007 | admission is checked | Passing denied activation tests | Proven |
| SKL-REQ-008 | resource policy is finite | Passing policy validation tests | Proven |
| SKL-REQ-009 | traversal guards exist | Passing path escape tests | Proven |
| SKL-REQ-010 | loading is bounded | Approved content normalization contract | Partial |
| SKL-REQ-011 | file count is bounded | Passing file count tests | Proven |
| SKL-REQ-012 | bytes are bounded | Passing byte limit tests | Proven |
| SKL-REQ-013 | resources are request-scoped | Passing isolation tests | Proven |
| SKL-REQ-014 | no global resource fallback | Passing fallback rejection tests | Proven |
| SKL-REQ-015 | action contributions exist | Full plugin and capability contribution proof | Partial |
| SKL-REQ-016 | registry lazily starts | Explicit supervised registry only | Conflict |
| SKL-REQ-017 | activation failures normalize | Passing error tests | Proven |
| SKL-REQ-018 | safe projections exist | Passing sanitization tests | Proven |
| SKL-REQ-019 | stable references are retained | Passing reference tests | Proven |
| SKL-REQ-020 | restore re-resolves resources | Passing restore tests | Proven |
| SKL-REQ-021 | missing resources fail | Passing missing-resource tests | Proven |
| SKL-REQ-022 | stale versions fail | Passing version mismatch tests | Proven |
| SKL-REQ-023 | live handles stay outside snapshots | Passing portability tests | Proven |
| SKL-REQ-024 | global fallback can own state | Host or session ownership only | Conflict |
| SKL-REQ-025 | checkpoint data is informal | Versioned activation codec | Partial |
| SKL-REQ-026 | broad examples exist | Complete legacy migration fixtures | Partial |

## Migration And Compatibility

- Keep current skill IDs, versions, and resource reference forms.
- Replace global registry lookup with an explicit injected host or session registry.
- During migration, allow a supervised compatibility registry only when the host declares it.
- Restore resources by identity and policy. Never restore a live provider, process, file handle, or function.

## Assumptions And Blockers

- Trusted hosts can configure function or MFA resource providers as live resources.
- Portable skill and checkpoint data cannot contain those live provider values.
- Package compile failure blocks final skill integration tests.

## Completion Criteria

- Skill activation is deterministic, bounded, and free of implicit process ownership.
- All resource reads enforce approved path, file count, byte, and content limits.
- Skill and resource checkpoint data is versioned and restore re-resolves live resources.
- All contribution collisions and migration cases pass tests.
