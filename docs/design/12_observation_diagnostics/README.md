> Seam review entry point. This document is pending approval.

# 12 — Observation and diagnostics

## Briefing

Jido AI emits telemetry, typed Signals, stream items, usage data, and diagnostic metadata. The target is one safe observation vocabulary for authored Agents and standalone requests. The main change is to separate user output, telemetry, and Signal transport while keeping one correlation and redaction model.

## Why this seam exists

- Owner: AI observation, telemetry, usage-event, and diagnostic modules.
- Owns: AI event names, measurements, metadata, correlation, redaction, safe inspection, and failure reporting.
- Does not own: A telemetry backend, log storage, Signal bus, provider dashboard, request control channel, or secret capture.

## Current and target state

| Area | Current | Target |
| --- | --- | --- |
| Telemetry | Observation and sanitization modules exist | One stable AI event vocabulary |
| Signals | Typed AI events exist | AI event data uses `jido_signal` transport |
| Streams | Token and progress items are emitted | Clear user-output and telemetry roles |

## Major gaps and work remaining

| Gap | Why it matters | Required outcome | Owner seam |
| --- | --- | --- | --- |
| Stable event set is not approved | Consumers can depend on incidental events | Versioned public event list | 12 |
| Default metadata policy is not final | Secrets or content can leak | Safe default allowlist and redaction rules | 12 |

## Decisions requested

1. **Public events:** Approve only request, model, tool, usage, and terminal lifecycle events as compatibility contracts.
   Effect: Internal diagnostic events can change safely.
2. **Metadata:** Approve an allowlist and redact content by default.
   Effect: Observation stays safe without host configuration.

## Dependencies

- Prerequisites: 00 through 11 for their event contracts; public core observe and `jido_signal` contracts.
- Dependents: 90.
- Blockers: Public event list and metadata policy.

## Documents

- [Target design](design.md).
- [Alignment plan](alignment.md).
