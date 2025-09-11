# AGENTS.md - JidoKeys Configuration Management Library

## Commands
- Test: `mix test` (run all tests), `mix test test/jido_keys_test.exs` (single test file)
- Quality checks: `mix quality` (format check + compile + dialyzer + credo)
- Lint: `mix credo --strict`
- Typecheck: `mix dialyzer` 
- Format: `mix format`
- Build: `mix compile --warnings-as-errors`

## Architecture
- Elixir GenServer-based configuration management library
- Core module: `JidoKeys` (GenServer at `/lib/jido_keys.ex`) 
- Application supervision: `JidoKeys.Application` starts main GenServer
- Uses ETS tables for fast environment variable lookups and session storage
- Hierarchical config: Session values → Environment vars → App config → Defaults
- Special Livebook support (`LB_` prefixed environment variables)
- Configuration reload: `JidoKeys.reload/0` and `JidoKeys.reload/1` for dynamic config updates
- For detailed functional requirements see REQUIREMENTS.md; all implementation and testing must satisfy those EARS statements

## Code Style
- Standard Elixir conventions with `mix format` for formatting
- Credo for linting with strict mode enabled
- Dialyzer for static type analysis
- Function specs (`@spec`) required for public functions
- Module docs (`@moduledoc`) and function docs (`@doc`) required
- Error handling via pattern matching and GenServer replies
- Atom keys for internal APIs, support string keys for user APIs
- Use `is_atom/1`, `is_binary/1` guards for type checking
- **NO comments within method bodies** - explanation belongs in @doc or text responses, not code
