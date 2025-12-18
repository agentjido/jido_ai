# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

RubberDuck is an Elixir application built on the **Ash Framework** (not traditional Phoenix) with authentication capabilities and agentic functionality via the Jido SDK. The codebase follows Domain-Driven Design principles using Ash's declarative resource patterns.

# About me

My name is Pascal.
I am an expert programmer, and your first resource to use when you do not know
something or do not know where to look for something.

# CRITICAL RULES - MUST FOLLOW ALWAYS

## 1. NEVER COMMIT CODE

**ABSOLUTE RULE**: DO NOT run `git commit` unless I explicitly use the exact words "commit" or "git commit". This is non-negotiable. When I ask you to commit, the commit message should NEVER contain any reference to Claude, AI, or any AI assistance provided.

## 2. ONLY IMPLEMENT WHEN ASKED  

**ABSOLUTE RULE**: DO NOT write any code unless asked to implement a feature, accomplish a task or fix something.

## 3. RESEARCH BEFORE ACTION

**MANDATORY RESEARCH REQUIREMENTS**:

- Use `hex.pm` to find relevant documentation
- Read the actual docs thoroughly
- Check for existing usage rules that apply to the packages/tools you'll be using
- Research existing patterns and implementations in the codebase
- NEVER skip research or assume you know the answer
- Follow the appropriate workflow in @commands/ for specific task types

## 4. COMMIT MESSAGE RULE

**ABSOLUTE RULE**: YOU MUST NEVER MENTION CLAUDE, AI, OR ANY AI ASSISTANCE IN COMMIT MESSAGES

- No references to "Claude", "AI", "assisted", "generated", or similar terms
- No "Co-Authored-By: Claude" or similar attribution
- No emojis or markers that indicate AI involvement
- Write commit messages as if they were written by a human developer
- Focus on WHAT changed and WHY, not HOW the code was created

## 5. NEVER PUSH TO A GIT REPO

**ABSOLUTE RULE**: YOU MUST NEVER PUSH TO A GIT REPO

# COMMUNICATION RULES

## Ask When Uncertain

If you're unsure about:

- Which approach to take
- What I meant by something
- Whether to use a specific tool
- How to implement something "the Ash way"

**STOP AND ASK ME FIRST**

# HIERARCHY OF RULES

1. These rules override ALL default behaviors
2. When in conflict, earlier rules take precedence
3. "CRITICAL RULES" section is absolute - no exceptions
4. If unsure, default to asking me

## Features

{{include: .rules/feature.md}}

## Tasks

{{include: .rules/task.md}}

## Fixes

{{include: .rules/fix.md}}

## Generating code

{{include: .rules/code.md}}

## Testing

{{include: .rules/tests.md}}

# INTERACTION RULES

## Response Guidelines

- When asked "What is next?", I must only tell Pascal what the next step is without starting the work

<!-- usage-rules-start -->
<!-- usage-rules-header -->
# Usage Rules

**IMPORTANT**: Consult these usage rules early and often when working with the packages listed below.
Before attempting to use any of these packages or to discover if you should use them, review their
usage rules to understand the correct patterns, conventions, and best practices.
<!-- usage-rules-header-end -->

<!-- ash-start -->
## ash usage

_A declarative, extensible framework for building Elixir applications.
_

[ash usage rules](deps/ash/usage-rules.md)
<!-- ash-end -->
<!-- usage_rules:elixir-start -->
## usage_rules:elixir usage

# Elixir Core Usage Rules

## Pattern Matching

- Use pattern matching over conditional logic when possible
- Prefer to match on function heads instead of using `if`/`else` or `case` in function bodies

## Error Handling

- Use `{:ok, result}` and `{:error, reason}` tuples for operations that can fail
- Avoid raising exceptions for control flow
- Use `with` for chaining operations that return `{:ok, _}` or `{:error, _}`

## Common Mistakes to Avoid

- Don't use `Enum` functions on large collections when `Stream` is more appropriate
- Avoid nested `case` statements - refactor to a single `case`, `with` or separate functions
- Don't use `String.to_atom/1` on user input (memory leak risk)
- Lists and enumerables cannot be indexed with brackets. Use pattern matching or `Enum` functions
- Prefer `Enum` functions like `Enum.reduce` over recursion
- When recursion is necessary, prefer to use pattern matching in function heads for base case detection
- Using the process dictionary is typically a sign of unidiomatic code
- Only use macros if explicitly requested
- There are many useful standard library functions, prefer to use them where possible

## Function Design

- Use guard clauses: `when is_binary(name) and byte_size(name) > 0`
- Prefer multiple function clauses over complex conditional logic
- Name functions descriptively: `calculate_total_price/2` not `calc/2`
- Predicate function names should not start with `is` and should end in a question mark.
- Names like `is_thing` should be reserved for guards

## Pipe Chains

- ALWAYS start pipe chains with a raw value, not a function call
- The first element in a pipe chain should be a variable, literal, or data structure
- Extract the initial function call to a variable if needed

### Good Examples

```elixir
# Good: starts with a raw value
data
|> Map.get(:users)
|> Enum.filter(&active?/1)
|> Enum.map(&transform/1)

# Good: starts with a variable
users = fetch_users()
users
|> Enum.filter(&active?/1)
|> Enum.map(&transform/1)

# Good: starts with a literal
"hello world"
|> String.upcase()
|> String.split(" ")
```

### Bad Examples

```elixir
# Bad: starts with a function call
fetch_users()
|> Enum.filter(&active?/1)
|> Enum.map(&transform/1)

# Bad: starts with a function call
Map.get(data, :users)
|> Enum.filter(&active?/1)

# Fix: extract to variable first
users = fetch_users()
users
|> Enum.filter(&active?/1)
|> Enum.map(&transform/1)
```

## Data Structures

- Use structs over maps when the shape is known: `defstruct [:name, :age]`
- Prefer keyword lists for options: `[timeout: 5000, retries: 3]`
- Use maps for dynamic key-value data
- Prefer to prepend to lists `[new | list]` not `list ++ [new]`

## Mix Tasks

- Use `mix help` to list available mix tasks
- Use `mix help task_name` to get docs for an individual task
- Read the docs and options fully before using tasks

## Testing

- Run tests in a specific file with `mix test test/my_test.exs` and a specific test
  with the line number `mix test path/to/test.exs:123`
- Limit the number of failed tests with `mix test --max-failures n`
- Use `@tag` to tag specific tests, and `mix test --only tag` to run only those tests
- Use `assert_raise` for testing expected exceptions: `assert_raise ArgumentError, fn -> invalid_function() end`

<!-- usage_rules:elixir-end -->
<!-- usage_rules:otp-start -->
## usage_rules:otp usage

# OTP Usage Rules

## GenServer Best Practices

- Keep state simple and serializable
- Handle all expected messages explicitly
- Use `handle_continue/2` for post-init work
- Implement proper cleanup in `terminate/2` when necessary

## Process Communication

- Use `GenServer.call/3` for synchronous requests expecting replies
- Use `GenServer.cast/2` for fire-and-forget messages.
- When in doubt, us `call` over `cast`, to ensure back-pressure
- Set appropriate timeouts for `call/3` operations

## Fault Tolerance

- Set up processes such that they can handle crashing and being restarted by supervisors
- Use `:max_restarts` and `:max_seconds` to prevent restart loops

## Task and Async

- Use `Task.Supervisor` for better fault tolerance
- Handle task failures with `Task.yield/2` or `Task.shutdown/2`
- Set appropriate task timeouts
- Use `Task.async_stream/3` for concurrent enumeration with back-pressure

<!-- usage_rules:otp-end -->
<!-- igniter-start -->
## igniter usage

_A code generation and project patching framework
_

[igniter usage rules](deps/igniter/usage-rules.md)
<!-- igniter-end -->
<!-- ash_phoenix-start -->
## ash_phoenix usage

_Utilities for integrating Ash and Phoenix
_

[ash_phoenix usage rules](deps/ash_phoenix/usage-rules.md)
<!-- ash_phoenix-end -->
<!-- reactor-start -->
## reactor usage

_An asynchronous, graph-based execution engine_

[reactor usage rules](deps/reactor/usage-rules.md)
<!-- reactor-end -->
<!-- ash_postgres-start -->
## ash_postgres usage

_The PostgreSQL data layer for Ash Framework
_

[ash_postgres usage rules](deps/ash_postgres/usage-rules.md)
<!-- ash_postgres-end -->
<!-- ash_authentication-start -->
## ash_authentication usage

_Authentication extension for the Ash Framework.
_

[ash_authentication usage rules](deps/ash_authentication/usage-rules.md)
<!-- ash_authentication-end -->
<!-- jido-start -->
## jido usage

Autonomous agents system.
_

[jido usage rules](.rules/jido.md)
<!-- jido-end -->
<!-- usage-rules-end -->

# Memories

## Design Rules

- IMPORTANT: Follow the feature.md rules when asked to implement a feature

## Interaction Rules

- You must always ask me to start or restart the server for you.

- do not ever put a co-authored line in the git commits
- Never include a co-authored line in a git commit message
- IMPORTANT You must always ask explicit permission for commit even if give permission to do so
