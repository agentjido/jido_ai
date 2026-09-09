> Seam review entry point. This document is pending approval.

# 02 — Model gateway and request preparation

## Briefing

Jido AI already resolves models and calls ReqLLM for text, object, and stream requests. The target is one provider-neutral gateway with explicit request data and host-bound provider resources. The main change is to make provider leakage, normalization, and option ownership explicit.

## Why this seam exists

- Owner: `Jido.AI`, `Jido.AI.Models`, model Actions, model routing, and request transforms.
- Owns: Model selection, request building, ReqLLM calls, response normalization, and model capabilities.
- Does not own: Agent lifecycle, tool execution, Flow execution, retry scheduling, credentials, or provider-client supervision.

## Current and target state

| Area | Current | Target |
| --- | --- | --- |
| Model calls | Shared facade and model modules use ReqLLM | One provider-neutral gateway |
| Options | Profile and request options can resolve at different times | Clear authoring-time and request-time ownership |
| Streaming | Supported by current model and runtime code | Stream and non-stream responses use the same normalization rules |

## Major gaps and work remaining

| Gap | Why it matters | Required outcome | Owner seam |
| --- | --- | --- | --- |
| Provider type boundary is not approved | Provider terms can become public API | Contract tests for provider-neutral values | 02 |
| Alias timing is not final | Portable definitions can change meaning | One alias resolution rule | 02 and 10 |

## Decisions requested

1. **Alias resolution:** Approve request-time resolution with explicit portable alias data.
   Effect: Hosts can change model routing without rewriting definitions.
2. **ReqLLM exposure:** Approve no ReqLLM structs in stable public results.
   Effect: Provider changes stay inside the gateway.

## Dependencies

- Prerequisites: [00 — Package boundary and invariants](../00_boundary_invariants/README.md) and [01 — AI values](../01_ai_values/README.md).
- Dependents: 04, 05, 08, 10, and 12.
- Blockers: Public value and output-repair decisions.

## Documents

- [Target design](design.md).
- [Alignment plan](alignment.md).
