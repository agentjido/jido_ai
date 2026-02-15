# Module-Wide Quality Expansion Plan (2.0 Beta, Post-PR #137)

This file supersedes `REACT_QUALITY_PLAN.md` as the canonical quality execution plan for the entire module.

## Scope
- Lifecycle parity and request closure across all strategies
- Hard namespace migration from `react.*`/`*.query` to `ai.*`
- Observability namespace and schema normalization
- Action-layer quality sweep (model schema alignment, tool-calling robustness, streaming lifecycle)
- Deterministic test infrastructure and de-skipping
- Docs/examples migration and strict 2.0-beta contract validation

## Contract
- 2.0-beta strict break
- No compatibility aliases
- No dual routing period

## Execution
Use `todo/module_quality_execution_checklist.md` as the implementation tracker and acceptance gate.
