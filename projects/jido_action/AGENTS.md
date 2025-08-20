# AGENT.md - Jido Action Development Guide

## Build/Test/Lint Commands
- `mix test` - Run tests (excludes flaky tests)
- `mix test path/to/specific_test.exs` - Run a single test file
- `mix test --include flaky` - Run all tests including flaky ones
- `mix quality` or `mix q` - Run full quality check (format, compile, dialyzer, credo)
- `mix format` - Auto-format code
- `mix dialyzer` - Type checking
- `mix credo` - Code analysis
- `mix coveralls` - Test coverage report
- `mix docs` - Generate documentation

## Architecture
This is an Elixir library for **composable action framework** with AI integration:
- **Jido.Action** - Core behavior for defining validated, composable actions
- **Jido.Exec** - Execution engine (sync/async, retries, timeouts, error handling)
- **Jido.Instruction** - Workflow composition system wrapping actions with params/context
- **Jido.Action.Tool** - Converts actions to AI-compatible tool definitions (OpenAI function calling)
- **Jido.Plan** - DAG (Directed Acyclic Graph) execution plans with dependency management
- **Jido.Tools.*** - 25+ pre-built tools (files, HTTP, arithmetic, GitHub, weather, workflow)

## Action Building Patterns
**Basic Actions** (see `test/support/test_actions.ex` for examples):
- Define schema with NimbleOptions for parameter validation
- Implement `run/2` callback returning `{:ok, result}` or `{:error, reason}`
- Use lifecycle hooks: `on_before_validate_params/1`, `on_after_run/1`, `on_error/4`
- Support output schemas for result validation

**Meta Actions** (see `lib/jido_tools/req.ex`):
- Use `__using__` macro to create action generators (e.g., HTTP request builders)
- `Jido.Tools.ReqTool` - HTTP client action generator with configurable URLs/methods
- `Jido.Tools.ActionPlan` - Plan execution action generator for complex workflows

**Plan-based Actions** (see `lib/jido_plan.ex`, `lib/jido_tools/action_plan.ex`):
- Create DAGs of actions with dependency management
- Support parallel execution phases based on dependency analysis
- Build workflows using `Plan.new() |> Plan.add/4` with `depends_on` relationships

## Code Style Guidelines
- Use `@moduledoc` for module documentation following existing patterns
- TypeSpecs: Define `@type` for custom types, use strict typing throughout
- Actions use `use Jido.Action` with compile-time config (name, description, schema, etc.)
- Parameter validation via NimbleOptions schemas in action definitions
- Error handling: Return `{:ok, result}` or `{:error, reason}` tuples consistently
- Module organization: Actions in `lib/jido_tools/`, core in `lib/jido_action/`
- Testing: Use ExUnit, test parameter validation and execution separately
- Naming: Snake_case for functions/variables, PascalCase for modules, descriptive action names
