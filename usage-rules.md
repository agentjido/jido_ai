# Jido AI Usage Rules

## Intent
Implement tool-using AI behavior with explicit model policy, bounded execution, and observable request flow.

## Core Contracts
- Prefer `Jido.AI.Actions.*` and `Jido.AI.Agent` over ad-hoc raw facade calls.
- Keep model alias, timeout, retry, and request policy explicit.
- Use **Zoi-first** schemas for structured inputs/outputs and tool contracts.
- Treat `ask`/`await` request handles as the safe concurrency boundary.
- Keep provider-specific logic behind ReqLLM integration points.
- Treat `agent_skills` filesystem discovery as an explicit trust boundary; runtime specs must use `source: nil`, carry inline bodies, and provider-backed resources must pass through `Jido.AI.Skill.ResourceProvider` validation.
- Preserve structured skill/resource errors and `ResourcePolicy` bounds for filesystem and provider-backed resources.
- Use `resource_id` for provider-backed resource loads; use `relative_path` for filesystem loads, with `path` retained only as a filesystem compatibility alias.
- Treat skill listing `resources` as the complete aggregate and `references`, `assets`, and `scripts` as filtered views. Entries intentionally appear in both views.

## Library Author Patterns
- Define tools as `Jido.Action` modules with small, deterministic behavior.
- Compose strategy agents (`ReAct`, `CoD`, `CoT`, `AoT`, etc.) by workload profile.
- Route AI outputs into domain actions instead of embedding domain mutation in prompts.
- Add telemetry hooks for request, LLM, and tool lifecycle events.

## QA Patterns
- Cover tool-call loops, request cancellation/timeouts, and fallback behavior.
- Keep a stable smoke subset (`mix test.fast`) plus full `mix quality` before release.
- Validate public examples when strategy/runtime behavior changes.

## Avoid
- Prompt-only pipelines with no schema validation or execution policy.
- Hidden model/provider defaults in production-critical paths.
- Unbounded tool retries/timeouts.

## References
- `README.md`
- `guides/`
- `AGENTS.md`
- https://hexdocs.pm/jido_ai
- https://hexdocs.pm/req_llm
- https://hexdocs.pm/usage_rules/readme.html#usage-rules
