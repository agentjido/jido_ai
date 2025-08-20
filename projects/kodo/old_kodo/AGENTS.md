# Agent Guide for Kodo

## Purpose
Kodo is an Elixir-native virtual shell system that provides multi-instance interactive sessions with virtual file system support. It's designed to be embedded in any BEAM application, offering an interactive REPL and full programmatic API for spawning sessions, evaluating commands, and manipulating virtual file systems with telemetry collection.

## Commands  
- **Test all**: `mix test`
- **Test single file**: `mix test test/kodo_test.exs`  
- **Test single test**: `mix test test/kodo_test.exs:123` (line number)
- **Quality check**: `mix quality` (format, compile, dialyzer, credo)
- **Format code**: `mix format`
- **Type check**: `mix dialyzer`
- **Lint**: `mix credo`
- **Coverage**: `mix coveralls`
- **Docs**: `mix docs`

## Architecture
- **Core Engine**: `lib/kodo/core/` - Organized into logical subdirectories by functionality
- **Session Management**: DynamicSupervisor for isolated session processes with Registry lookup
- **Virtual File System**: Built on Depot adapter pattern for polymorphic storage backends
- **Ports & Adapters**: Behaviours for commands, transports, and file systems
- **Built-in Commands**: `lib/kodo/commands/` - cd, ls, pwd, env, jobs, fg, bg, kill
- **Transport Layer**: `lib/kodo/transports/` - IEx integration with extensible transport behaviours
- **Job Control**: Background/foreground process management with kill/wait operations

## File Structure
```
lib/kodo/
├── commands/          # Built-in commands (cd, pwd, ls, env, help, jobs, fg, bg, kill)
├── core/              # Core engine components
│   ├── parsing/       # Command & shell parsing (command_parser, shell_parser, execution_plan, command_macro)
│   ├── execution/     # Command execution engines (executor, builtin_executor, external_executor, pipeline_executor, command_runner, command_context)
│   ├── sessions/      # Session management (session, session_supervisor, stdio_manager)
│   ├── jobs/          # Job control system (job, job_manager)
│   └── commands/      # Command registry (command_registry)
├── vfs/               # Virtual file system (vfs, manager, supervisor)
├── transports/        # Transport implementations (iex)
├── executors/         # Process executor implementations (local)
└── ports/             # Behaviors/interfaces (command, filesystem, process_executor, transport)
```

## Code Style
- Use `mix format` for consistent formatting (configured in `.formatter.exs`)
- Follow Elixir naming: snake_case for functions/variables, PascalCase for modules  
- Pattern match with `{:ok, result}` | `{:error, reason}` tuples
- Prefer `with` statements for error handling chains
- Use `@spec` type annotations for public functions
- Test with ExUnit, use `assert_in_list/2` macro for list assertions
- Group related tests in `describe` blocks with setup context

- test scripts live in `scripts/`