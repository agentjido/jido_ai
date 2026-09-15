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

For the V3 cleanup, run these checks from this repository in zsh:

```sh
mix format --check-formatted
mix compile --force --warnings-as-errors
unit_tests=(${(f)"$(rg --files test/jido_ai test/jido_ai_test.exs -g '*_test.exs' -g '!test/jido_ai/authoring/**' | sort)"})
mix test "${unit_tests[@]}" --warnings-as-errors --seed 0
```

This selection includes the deterministic runtime integration tests. Authoring
and example suites are deferred during this cleanup. Keep the existing flaky
exclusion; add no skips or ignored failures. See `docs/v3-spike/simplification.md`
for verified results and the remaining repairs.

## Architecture Snapshot
- `Jido.AI.Agent` + `Jido.AI.DSL` + `Jido.AI.Profile` is the main V3 authoring model.
- `Authoring` lowers validated Profiles into core Agents and Flows. Profile
  owns defaults, policy validation, schemas, and validation errors. Its internal
  `Profile.References` module resolves explicit registry references without execution.
- Request, Session, and runtime Plugins manage execution. Session inspection
  reads the selected Profile and committed History. The root strategy inspection
  helpers and execution CLI are removed.
- Keep all eight reasoning methods and the standalone ReAct API.
- `Jido.AI.Actions.*`: reusable runtime actions for chat/tool/structured flows
- ReqLLM integration for provider abstraction and model routing
- Policy/observability modules for retries, quotas, telemetry, and traceability
- `Jido.Session` and `Jido.Thread` are currently defined in this repository.
  Their intended package ownership remains undecided. Keep Session.Runtime's
  process and commit responsibilities together.

## Standards
- Keep model selection, timeout, retry, and tool policy explicit
- Use **Zoi-first** schemas for tool inputs and structured outputs
- Keep provider-specific behavior behind ReqLLM integration boundaries
- Preserve tagged tuple and structured error contracts
- Prefer deterministic fallback behavior over ad-hoc prompt pipelines

## Testing and QA
- Cover strategy behavior, tool-call loops, and error/fallback handling
- Keep flaky tests isolated behind tags; maintain a stable smoke subset (`mix test.fast`)
- Outside the bounded V3 cleanup, validate affected examples and scripts when
  runtime behavior changes. Record deferred repairs during the cleanup.

## Release Hygiene
- Work on `v3-spike` for this cleanup. `mix.exs` currently declares package
  version `2.3.0`, V3 beta ecosystem dependencies, and a pinned ReqLLM Git ref.
  These values do not declare a completed V3 release. Keep dependency versions
  and pins unchanged unless the task requires a dependency change.
- Use Conventional Commits
- Do not modify `CHANGELOG.md`; release notes are generated from Git history during release, so keep changes focused on proper Conventional Commits.
- Update guides and migration notes for behavior/API changes

## References
- `README.md`
- `usage-rules.md`
- `guides/`
- https://hexdocs.pm/jido_ai
