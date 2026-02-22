# AGENTS.md - Jido.AI Guide

## Intent
Build tool-using AI agents with explicit strategy, runtime policy, and reliable request orchestration.

## Runtime Baseline
- Elixir `~> 1.18`
- OTP `27+` (release QA baseline)

## Commands
- `mix test` (default alias excludes `:flaky`)
- `mix test.fast` (stable smoke suite)
- `mix precommit` (`format`, `compile --warnings-as-errors`, `doctor --summary --raise`, `test.fast`)
- `mix q` or `mix quality` (`format`, `compile`, `credo`, `doctor`, `dialyzer`)
- `mix docs`

## Architecture Snapshot
- `Jido.AI.Agent` + strategy agents (`CoD`, `CoT`, `AoT`, `ToT`, `GoT`, `TRM`, `Adaptive`)
- `Jido.AI.Actions.*`: reusable runtime actions for chat/tool/structured flows
- ReqLLM integration for provider abstraction and model routing
- Policy/observability modules for retries, quotas, telemetry, and traceability

## Standards
- Keep model selection, timeout, retry, and tool policy explicit
- Use **Zoi-first** schemas for tool inputs and structured outputs
- Keep provider-specific behavior behind ReqLLM integration boundaries
- Preserve tagged tuple and structured error contracts
- Prefer deterministic fallback behavior over ad-hoc prompt pipelines

## Testing and QA
- Cover strategy behavior, tool-call loops, and error/fallback handling
- Keep flaky tests isolated behind tags; maintain a stable smoke subset (`mix test.fast`)
- Validate public examples/scripts when runtime behavior changes

## Release Hygiene
- Keep semver ranges stable (`~> 2.0` ecosystem peers; package currently `2.0.0-rc.0`)
- Use Conventional Commits
- Update `CHANGELOG.md`, guides, and migration notes for behavior/API changes

## References
- `README.md`
- `usage-rules.md`
- `guides/`
- https://hexdocs.pm/jido_ai
