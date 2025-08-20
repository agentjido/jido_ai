# Agent Guide for Kodo (v2)

## Purpose
Kodo is an Elixir-native virtual shell system that provides multi-instance interactive sessions with virtual file system support. It's designed to be embedded in any BEAM application, offering an interactive REPL and full programmatic API for spawning sessions, evaluating commands, and manipulating virtual file systems with telemetry collection.

## Commands
- **Interactive shell**: `mix kodo` - Easy entry point into the shell
- **Compiler Warnings**: `mix compile --warnings-as-errors`
- **Test all**: `mix test`
- **Test single file**: `mix test test/kodo_test.exs`
- **Test single test**: `mix test test/kodo_test.exs:123` (line number)
- **Quality check**: `mix quality` (format, compile, dialyzer, credo)
- **Format code**: `mix format`
- **Type check**: `mix dialyzer`
- **Lint**: `mix credo`
- **Docs**: `mix docs`

## High-Level Architecture Components

### 1. Instance Management
- **Purpose**: Isolated Kodo environments with dedicated VFS, command registry, and sessions
- **Design**: Each instance runs as supervised process tree with configurable filesystem mounts and command sets
- **Configuration**: Each instance can customize available commands and mounted filesystems for complete environment isolation

### 2. Virtual File System (VFS)
- **Purpose**: Mount multiple filesystem adapters at different paths with unified API over Depot adapters
- **Features**: Search, stats, batch operations, revision control, cross-filesystem copy/move
- **Design**: Manager routes operations to appropriate mounted filesystem based on path resolution

### 3. Session Management
- **Purpose**: Interactive shell sessions with command history, environment variables, Elixir bindings
- **Design**: Dynamic supervisor manages multiple concurrent sessions per instance

### 4. Command Execution Engine
- **Components**:
  - **Parser**: NimbleParsec-based shell syntax parser
  - **Execution**: Pipeline execution with pipes and redirections
  - **Executors**: Built-in and external command support
- **Features**: Layered execution with plan generation, process lifecycle management

### 5. Transport & Adapter Layers
- **Port Behaviors**: Clean contracts for Transport, Command, FileSystem, and Execution
- **Implementations**: Built-in commands (cd, ls, pwd, etc.)
- **Transport**: IEx integration with ANSI formatting, extensible to WebSocket, SSH, etc.

## Key Design Patterns
- **Ports & Adapters**: Clean separation between domain logic and adapters
- **Hexagonal Architecture**: Clear boundaries with behavior contracts
- **OTP Supervision**: Proper supervision trees with fault tolerance
- **Registry-based Lookup**: O(1) instance/session access
- **Telemetry**: Comprehensive observability throughout the system

## Code Style
- Use `mix format` for consistent formatting (configured in `.formatter.exs`)
- Follow Elixir naming: snake_case for functions/variables, PascalCase for modules
- Pattern match with `{:ok, result}` | `{:error, reason}` tuples
- Prefer `with` statements for error handling chains
- Use `@spec` type annotations for public functions
- Test with ExUnit, group related tests in `describe` blocks with setup context

## Testing Framework
- **Kodo.Case**: Centralized test case template providing isolated test environments
- **Features**: Each test gets its own Instance, Session, and CommandRegistry for isolation
- **Utilities**: Helper functions for unique atoms, process monitoring, command execution
- **Configuration**: Logger level warning, capture_log enabled, async tests supported