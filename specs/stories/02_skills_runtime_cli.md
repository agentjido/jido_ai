# Skills + Runtime + CLI Stories

### ST-SKL-001 Jido AI Skills End-To-End Hardening
#### Goal
Complete docs/tests/examples coverage for the skills system and skill-oriented CLI workflows.
#### Scope
- Cover `Jido.AI.Skill`, `Spec`, `Loader`, `Registry`, and `Prompt` contracts.
- Cover `mix jido_ai.skill` command surface and error handling.
- Validate and document `priv/skills/*` examples and script usage.
#### Acceptance Criteria
- Skills docs include lifecycle and failure-mode guidance.
- Skills runtime tests include happy path, validation failure, and registry lifecycle.
- Skill demos/scripts are current and runnable with clear prerequisites.
#### Stable Test Gate
- `mix precommit`
- `mix test.fast`
- `mix test test/jido_ai/skill`
- `mix test test/jido_ai/skills`
#### Docs Gate
- `mix doctor --summary`
- `mix docs`
#### Example Gate
- `mix run lib/examples/scripts/skill_demo.exs` (or documented skip path when API keys/files are absent).
#### Dependencies
- ST-OPS-001
- ST-OPS-002

### ST-RTC-001 Core Runtime Contracts End-To-End
#### Goal
Ensure request lifecycle and runtime contract modules are consistently documented, tested, and example-driven.
#### Scope
- Cover `Request`, `Turn`, `Thread`, and directive runtime behavior docs/tests.
- Validate request rejection, await, and concurrency contract consistency.
#### Acceptance Criteria
- Core runtime guides map directly to runtime modules and integration tests.
- Tests assert happy path, busy/rejection path, and lifecycle completion path.
- No contract drift between docs, signal emissions, and tests.
#### Stable Test Gate
- `mix precommit`
- `mix test.fast`
- `mix test test/jido_ai/request_test.exs test/jido_ai/turn_test.exs test/jido_ai/thread_test.exs`
- `mix test test/jido_ai/integration/request_lifecycle_parity_test.exs`
#### Docs Gate
- `mix doctor --summary`
#### Example Gate
- Add/refresh one runtime-focused example snippet in guides.
#### Dependencies
- ST-OPS-001
- ST-OPS-002

### ST-RTC-002 Signals Observability Security End-To-End
#### Goal
Close coverage gaps across signals, observability, validation, and sanitization contracts.
#### Scope
- Cover `Observe`, `Signals.*`, `Validation`, and `Error.Sanitize` modules.
- Ensure docs define event contracts and redaction/error handling behavior.
#### Acceptance Criteria
- Signal namespace contract docs match emitted signal types.
- Security and sanitization tests cover sensitive/error edge cases.
- Observability behavior has clear enable/disable and metadata contract docs.
#### Stable Test Gate
- `mix precommit`
- `mix test.fast`
- `mix test test/jido_ai/observe_test.exs test/jido_ai/signal_test.exs test/jido_ai/error/sanitize_test.exs test/jido_ai/validation_test.exs`
#### Docs Gate
- `mix doctor --summary`
#### Example Gate
- At least one example snippet demonstrates telemetry/signal usage.
#### Dependencies
- ST-OPS-001
- ST-OPS-002

### ST-RTC-003 CLI Surface End-To-End
#### Goal
Ensure `mix jido_ai` and CLI adapters are fully documented, tested, and supported by examples.
#### Scope
- Cover CLI task options, adapter mapping, and error formatting.
- Verify adapter tests align with supported strategy list.
- Update `guides/user/cli_workflows.md` examples and constraints.
#### Acceptance Criteria
- CLI docs include one-shot, stdin mode, and agent-module mode coverage.
- Adapter tests cover default and custom configuration for each strategy type.
- No stale paths or unsupported flags in CLI guide.
#### Stable Test Gate
- `mix precommit`
- `mix test.fast`
- `mix test test/jido_ai/cli/adapters`
#### Docs Gate
- `mix doctor --summary`
#### Example Gate
- Add or refresh one script/guide block that exercises `mix jido_ai --type <strategy>`.
#### Dependencies
- ST-OPS-001
- ST-OPS-002
