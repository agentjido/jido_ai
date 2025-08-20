# AGENT.md - Jido HTN Development Guide

Jido HTN is an Elixir package for defining and executing Hierarchical Task Networks. It is a component of the `jido` ecosystem, building on Jido primitives like `jido_action`

## Module prefixs & folder structure

- `Jido.HTN` - The main module for the package
- `Jido.HTNTest` - The module for testing the package
- `lib/jido_htn/` - The main folder for the package
- `lib/jido_htn/jido_htn.ex` - The main module for the package
- `test/jido_htn_test.exs` - The test file for the package
- `test/jido_htn/` - The test folder for the package

## Commands & Quality

- **Test**: `mix test` (all), `mix test test/path/to/file.exs` (single), `mix test --trace` (verbose)
- **Lint**: `mix credo` (basic), `mix credo --strict` (strict)
- **Format**: `mix format` (format), `mix format --check-formatted` (check)
- **Quality**: `mix quality` or `mix q` (runs format, compile, dialyzer, credo, doctor, docs)
- **Compile**: `mix compile` (basic), `mix compile --warnings-as-errors` (strict)
- **Type Check**: `mix dialyzer --format dialyxir`
- **Coverage**: `mix test --cover` (basic), `mix coveralls.html` (HTML report)
- **Docs**: `mix docs` (generate documentation)

## Code & SDLC Guidelines

- **Coverage**: Target 80%+ test coverage
- **Quality**: Use `mix quality` to check formatting, compilation, types, and docs; fix all warnings
- **Types & Specs**: Add `@type` to all custom types, `@spec` to all public functions
- **Docs**: Use `@moduledoc` for modules, `@doc` for public functions (with examples)
- **Style**: Max line length 120, `snake_case` for functions/vars, `PascalCase` for modules
- **Testing**: Mirror `lib/` in `test/`, use ExUnit async, tag slow/integration tests, prefer Req.Test for HTTP mocking
- **Error Handling**: Return `{:ok, result}`/`{:error, reason}` tuples, use `with` for complex flows
- **Imports**: Group aliases at top, prefer explicit over wildcard imports
- **Logging**: Avoid Logger metadata; include all fields in log message strings

### Error Handling

- **Error Handling**: Leverage the `splode` package for error handling
- **Error Module**: Create a new error module for the package, e.g. `Jido.HTN.Error` based on `splode` in `lib/jido_htn/error.ex`
  - Define Splode Error modules as needed
  - Seek to reuse Splode Error modules wherever possible
  - Splode tutorial: https://raw.githubusercontent.com/ash-project/splode/refs/heads/main/documentation/tutorials/get-started-with-splode.md

## Automatic GIT Commit

- 

## Architecture

__TODO__

## Public API Overview

__TODO__

## Data Architecture

__TODO__

## Jido Action Integration

This package is designed to be used with `jido_action`. Jido Action modules must implement a `run/2` method.

Actions are the modules that are executed within a PrimitiveTask in the HTN.
