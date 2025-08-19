# Jido Signal - Agent Guide

## Build/Test/Lint Commands
- `mix deps.get` - fetch dependencies
- `mix test` - run full test suite (excludes flaky tests)
- `mix test test/path/to/file_test.exs` - run single test file
- `mix test test/path/to/file_test.exs:42` - run single test at line 42
- `mix test --exclude flaky` bypassed by running plain `mix test` for debugging
- `mix q` or `mix quality` - format, compile with warnings-as-errors, dialyzer, credo
- `mix format` - format code, `mix compile --warnings-as-errors` - strict compilation
- `mix coveralls.html` - test coverage report

## Architecture
- OTP application with supervision tree: `Jido.Signal.Supervisor` → Registry + Task.Supervisor
- Main modules: `Jido.Signal` (struct), `Jido.Signal.Bus` (GenServer pub/sub), `Jido.Signal.Router` (pattern matching)
- Dispatch adapters: `:pid`, `:pubsub`, `:http`, `:bus`, `:named`, `:console`, `:logger`, `:noop`
- In-memory persistence via ETS or maps, no external DB dependency
- Middleware pipeline for cross-cutting concerns

## Code Style
- snake_case functions, PascalCase modules under `Jido.Signal.*`
- TypedStruct for struct definitions with enforced keys & types
- Extensive `@moduledoc`/`@doc` with parameters, returns, examples
- Error handling: `{:error, Jido.Signal.Error.t()}` or atoms
- `with...do` pipelines for public API functions
- Pattern matching guards, early validation with NimbleOptions
- Tests use ExUnit, Mimic for mocking, tags `:capture_log`, `:flaky`, `:skip`
