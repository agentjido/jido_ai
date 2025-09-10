# AGENTS.md - ReqLLM Development Guide

## Project Overview
ReqLLM is a composable Elixir library for AI interactions built on Req, providing a unified interface to AI providers through a plugin-based architecture.

## Common Commands

### Build & Test
- `mix test` - Run all tests
- `mix test test/req_llm_test.exs` - Run specific test file
- `mix test --only describe:"model/1 top-level API"` - Run specific describe block
- `mix compile` - Compile the project
- `mix quality` or `mix q` - Run quality checks (format, compile --warnings-as-errors, dialyzer, credo)

### Code Quality
- `mix format` - Format Elixir code
- `mix format --check-formatted` - Check if code is properly formatted
- `mix dialyzer` - Run Dialyzer type analysis
- `mix credo --strict` - Run Credo linting

## Architecture & Structure

### Core Structure
- `lib/req_llm.ex` - Main API facade with generate_text/3, stream_text/3, generate_object/4
- `lib/req_llm/` - Core modules (Model, Provider, Plugin, Error structures)
- `lib/req_llm/providers/` - Provider-specific implementations (Anthropic, etc.)
- `test/` - Test files following ExUnit patterns
- `test/support/` - Test support modules and helpers

### Plugin Architecture
- Each provider implements `ReqLLM.Plugin` behavior with `attach/2` and `parse/2` callbacks
- Providers use `ReqLLM.Provider.DSL` macro for registration and metadata loading
- Core API uses `ReqLLM.attach/2` to compose Req requests with provider plugins

## Code Style & Conventions

### General Style
- Follow standard Elixir conventions and use `mix format` for consistent formatting
- Use `@moduledoc` and `@doc` for comprehensive documentation
- Prefer pattern matching over conditionals where possible
- Use `{:ok, result}` / `{:error, reason}` tuple returns for fallible operations

### Imports & Dependencies
- Minimize imports, prefer explicit module calls (e.g., `ReqLLM.Model.from/1`)
- Group deps in mix.exs: runtime deps first, then dev/test deps with `, only: [:dev, :test]`

### Types & Validation
- Use TypedStruct for structured data with `@type` definitions
- Validate options with NimbleOptions schemas in public APIs
- Use Splode for structured error handling with specific error types

### Error Handling
- Return `{:ok, result}` or `{:error, %ReqLLM.Error{}}` tuples
- Use Splode error types: `ReqLLM.Error.API`, `ReqLLM.Error.Parse`, `ReqLLM.Error.Auth`
- Include helpful error messages and context in error structs

### Testing
- Use ExUnit with `async: true` for most tests
- Group related tests in `describe` blocks
- Use descriptive test names that explain the expected behavior
- Mock HTTP requests using Mimic for provider integration tests
