# Agent Guide for Depot

## Commands
- **Test all**: `mix test`
- **Test single file**: `mix test test/depot_test.exs`  
- **Test single test**: `mix test test/depot_test.exs:123` (line number)
- **Quality check**: `mix quality` (format, compile, dialyzer, credo)
- **Format code**: `mix format`
- **Type check**: `mix dialyzer`
- **Lint**: `mix credo`
- **Coverage**: `mix coveralls`
- **Docs**: `mix docs`

## Architecture
- **Core**: Filesystem abstraction library with adapter pattern
- **Adapters**: `lib/depot/adapter/` - Local, InMemory, S3 adapters
- **Main API**: `lib/depot.ex` - Unified filesystem operations (read, write, copy, move, delete)
- **Support**: Virtual filesystem, stat structs, visibility controls, relative path handling
- **Test setup**: Minio server for S3 testing, tmp_dir fixtures, async tests

## Code Style
- Use `mix format` for consistent formatting (configured in `.formatter.exs`)
- Follow Elixir naming: snake_case for functions/variables, PascalCase for modules  
- Pattern match with `{:ok, result}` | `{:error, reason}` tuples
- Prefer `with` statements for error handling chains
- Use `@spec` type annotations for public functions
- Test with ExUnit, use `assert_in_list/2` macro for list assertions
- Group related tests in `describe` blocks with setup context
