# AGENTS.md - ReqLLM Development Guide

## Commands

- **Test**: `mix test` (all), `mix test test/path/to/specific_test.exs` (single file), `mix test --trace` (verbose)
- **Quality**: `mix quality` (runs format, compile with warnings, dialyzer, credo)
- **Format**: `mix format` (format code), `mix format --check-formatted` (verify formatting)
- **Compile**: `mix compile` (basic), `mix compile --warnings-as-errors` (strict)
- **Type Check**: `mix dialyzer`
- **Coverage**: `mix test --cover` (basic coverage report)
- **Scripts**: Always use `mix run script_name.exs` to run test scripts - avoids Mix.install conflicts

## Architecture

ReqLLM is a simplified Elixir library for AI interactions built on Req HTTP client:

- **Core**: [`lib/req_llm.ex`](lib/req_llm.ex) - Main API facade
- **Messages**: [`lib/req_llm/message.ex`](lib/req_llm/message.ex) - Multi-modal message structures
- **ObjectSchema**: [`lib/req_llm/object_schema.ex`](lib/req_llm/object_schema.ex) - Schema definitions with JSON Schema export
- **Error**: [`lib/req_llm/error.ex`](lib/req_llm/error.ex) - Splode-based error handling
- **Provider**: [`lib/req_llm/provider/`](lib/req_llm/provider/) - Simple provider system with Registry and Behavior

## SDLC

- **Coverage Goal**: Target 75%+ test coverage (simpler than jido_ai's 90%+)
- **Code Quality**: Use `mix quality` to run all checks
  - Fix all compiler warnings
  - Fix all dialyzer warnings
  - Add `@spec` to all public functions
  - Add `@doc` to all public functions and `@moduledoc` to all modules

## Code Style

- **Comments Rule**: NEVER add inline comments within method boundaries. Keep code self-documenting. Only use module-level docs (@moduledoc, @doc).
- **Formatting**: Uses `mix format`, line length max 120 chars
- **Types**: Add `@spec` to all public functions, use TypedStruct for data structures
- **Docs**: `@moduledoc` for modules, `@doc` for public functions with examples
- **Testing**: Mirror lib structure in test/, use ExUnit, target 75%+ coverage, keep tests terse and focused
- **Error Handling**: Use Splode for consistent error handling, return `{:ok, result}` or `{:error, reason}` tuples
- **Dependencies**: Minimal deps (req, jason, typed_struct, splode, nimble_options)
- **Naming**: `snake_case` for functions/variables, `PascalCase` for modules
- **Simplicity**: Keep it simple - fewer abstractions than jido_ai, more direct implementations

## Project Goals

ReqLLM is designed to be a simpler, more focused alternative to jido_ai with:

1. **Simplified Provider System**: Minimal registry, direct implementations
2. **Clean Message Structures**: Multi-modal support without complexity
3. **Focused ObjectSchema**: JSON Schema export for LLM integration
4. **Consistent Error Handling**: Splode-based error management
5. **High Quality, Low Complexity**: 75%+ coverage with terse, focused tests
