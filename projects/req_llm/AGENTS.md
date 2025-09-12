# AGENTS.md - ReqLLM Development Guide

## Project Overview
ReqLLM is a composable Elixir library for AI interactions built on Req, providing a unified interface to AI providers through a plugin-based architecture.

## Common Commands

### Build & Test
- `mix test` - Run all tests
- `mix test test/req_llm_test.exs` - Run specific test file
- `mix test --only describe:"model/1 top-level API"` - Run specific describe block
- `LIVE=true mix test` - Run the same test suites against the real APIs and (re)generate fixtures
- `FIXTURE_FILTER=anthropic mix test` - Limit fixture regeneration to a single provider (supported by LiveFixture)
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
- `test/` - Consolidated capability-oriented test suites
  - `core_test.exs`, `streaming_test.exs`, `tool_calling_test.exs`, etc.
  - `coverage/<provider>/` - Optional provider-specific capability tests
  - `support/` - shared helpers (e.g. `live_fixture.ex`, factories)
  - Test files are intentionally few and broad; new behavior should extend an existing suite when possible instead of adding many micro-tests

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
- **No inline comments in method bodies** - code should be self-explanatory through clear naming and structure

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

### Testing & Fixture Workflow
- Tests are grouped by *capability*, not by individual function-call
- All suites use `ReqLLM.Test.LiveFixture.use_fixture/3` to abstract live vs cached responses
- Cached JSON fixtures live next to the test in `fixtures/<provider>/<test_name>.json` and are automatically written when the `LIVE=true` env-var is set
- Most suites run `async: true`. Suites that write fixtures are forced to synchronous execution via `@moduletag :capture_log`
- Mimic is still used for boundary mocks (timeouts, network-errors) that cannot be recorded

```elixir
defmodule CoreTest do
  use ReqLLM.Test.LiveFixture, provider: :openai
  use ExUnit.Case, async: true

  describe "generate_text/3" do
    test "basic happy-path" do
      {:ok, text} =
        use_fixture(:provider, "core-basic", fn ->
          ReqLLM.generate_text!("openai:gpt-4o", "Hello!")
        end)

      assert text =~ "Hello"
    end
  end
end
```
