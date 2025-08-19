KODO_FEATURES.md
================

1. Project overview
-------------------

Kodo is an Elixir-native "virtual shell" that can be embedded in any BEAM application.  
It offers an interactive REPL (via IEx by default) plus a full programmatic API for spawning
sessions, evaluating commands, manipulating a virtual file-system and collecting telemetry.
Its design follows a hexagonal/ports-and-adapters style so that transports, commands,
and storage back-ends can be swapped without touching the core engine.

Typical use cases
• Shipping an interactive maintenance shell inside a Phoenix / Nerves /
  Livebook or CLI app  
• Scripting & task automation with Elixir semantics while keeping familiar
  *nix-style syntax  
• Teaching / demo environments where the real host FS or OS should not be
  exposed.

2. Core feature list
--------------------

| Area                     | Capabilities |
|--------------------------|--------------|
| Interactive REPL         | Coloured prompt, history, `exit`, error formatting |
| Multiple sessions        | DynamicSupervisor keeps isolated Session processes; Registry for lookup/telemetry |
| Command parsing          | Custom grammar with NimbleParsec supporting tokens, quotes, escapes, pipes (`|`), redirections (`< > >>`), control ops (`&& || ;`), background `&` |
| Execution engine         | Builds ExecutionPlan structs, executes via PipelineExecutor (pipes), BuiltinExecutor or ExternalExecutor, and ties into JobManager |
| Job control              | `jobs`, `fg`, `bg`, `kill` built-ins; foreground/background swap; wait, kill, exit status |
| Built-in commands        | `help`, `cd`, `pwd`, `ls`, `env`, `jobs`, `fg`, `bg`, `kill` (*all in Elixir, pure/in-proc*) |
| External commands        | Fallback to OS via Port + StdioManager; pipes supported |
| Virtual file system      | Polymorphic FS through Depot adapter; high-level helpers for search, stats, batch rename, etc. |
| Telemetry & logging      | Rich events for command exec, FS operations, error tracking; default console handlers attached at app start |
| Extensibility            | • `Kodo.Ports.Command` behaviour  
                           • `Kodo.Core.CommandMacro` for boiler-free builtin definition  
                           • `Kodo.Ports.Transport` and `Kodo.Ports.FileSystem` behaviours |

3. Architectural snapshot
-------------------------

Supervision tree (simplified):

```
Kodo.Supervisor
 ├─ Registry : Kodo.SessionRegistry
 ├─ DynamicSupervisor : Kodo.Core.SessionSupervisor (shell sessions)
 ├─ GenServer : Kodo.Core.CommandRegistry (builtin registry)
 ├─ GenServer : Kodo.Core.JobManager
 ├─ Supervisor  : Kodo.VFS.Supervisor (Virtual FS back-end(s))
 └─ Task        : register_default_commands/0
```

High-level layers

```
┌──────────────────────── Ports (behaviours) ─────────────────────────┐
│  Command  Transport  FileSystem                                    │
└────────────────────────────┬───────────────────────────────────────┘
                             │ implemented by
┌──────────────┐  ┌───────────────────────────┐  ┌─────────────────┐
│Adapters.Cmds │  │Transport (IEx, custom …)  │  │FS adapters      │
├──────────────┤  └───────────────────────────┘  └─────────────────┘
│ cd ls env…   │
└──────────────┘
        ▲ call                    ┌────────────────────────────┐
        │                         │ Kodo.Core (engine layer)   │
        │                         │ • ShellParser / CmdParser  │
        │                         │ • ExecutionPlan            │
        │                         │ • CommandRunner            │
        │                         │ • PipelineExecutor         │
        │                         │ • Builtin & External exec  │
        │                         │ • JobManager               │
        │                         │ • StdioManager             │
        │                         └────────────────────────────┘
        │
┌───────┴───────┐
│Kodo.Shell API │  (public façade)
└───────────────┘
```

4. Component walkthrough
------------------------

### Ports (behaviours)

• `Kodo.Ports.Command` – canonical callback spec (`name/0`, `execute/2`, etc.)  
• `Kodo.Ports.Transport` – start/stop/write for any UI/channel  
• `Kodo.Ports.FileSystem` – abstract FS CRUD; default impl delegates to Depot.

### Core subsystem (`lib/kodo/core`)

| Module | Responsibility |
|--------|----------------|
| `ShellParser` | NimbleParsec grammar → AST tokens |
| `CommandParser` | user-friendly façade; legacy simple parsing; converts to ExecutionPlan |
| `ExecutionPlan` (structs) | Command, Pipeline, Redirection descriptors |
| `CommandRunner` | Entry point -> chooses builtin vs external, foreground/background |
| `BuiltinExecutor` | Safe wrapper around built-ins with telemetry/error capture |
| `ExternalExecutor` | (not shown in diff) spawns OS processes via `Port` |
| `PipelineExecutor` | Connects stdio, manages control operators, waits or backgrounds |
| `Job` struct + `JobManager` | Lifecycle, IDs, foreground/background, wait/kill |
| `StdioManager` | Central place for pipe setup & `Port` IO (simplified yet) |
| `Session` | Per-user REPL state (env, history, Elixir bindings) |
| `SessionSupervisor` | DynamicSupervisor for sessions |
| `CommandRegistry` | GenServer mapping command names ⇒ module |

### VirtualFS (`core/virtual_fs*`, `Kodo.VFS.Supervisor`)

Supervisor + server wrapping Depot adapter; provides helpers
`search/4`, `stats/3`, `batch_rename/5` in addition to CRUD.

### Adapters

• `lib/kodo/adapters/basic_cmd.ex` – groups `cd`, `pwd`, `ls`, `env`, `help`.  
• `adapters/commands/bg.ex`, `fg.ex`, `jobs.ex`, `kill.ex` – job control.  
All declare `@behaviour Kodo.Ports.Command` and are auto-registered at app start.

### Transports

• `Kodo.Transport.IEx` – IEx console loop with ANSI colour, integrates with Session, shows errors nicely.  
Additional transports (websocket, SSH, Livebook) can be added by implementing the behaviour.

### Telemetry

`Kodo.Telemetry` centralises event emission; application start attaches default console logging
but users can hook any `:telemetry` consumer for metrics or tracing.

5. Key modules at a glance
--------------------------

| Module | Key Functions |
|--------|---------------|
| `Kodo.Shell` | `start/1`, `eval/2`, `pwd/1`, `cd/2`, convenience over core |
| `Kodo.Application` | Boot sequence & default command registration |
| `Kodo.Core.CommandMacro` | `defcommand/3` – DSL for defining built-ins in one block |
| `Kodo.Core.JobManager` | `start_job/4`, `bring_to_foreground/1`, `send_to_background/1`, `kill_job/1`, `wait_for_job/2` |
| `Kodo.Transport.IEx` | GenServer loop: reads IO, forwards to `CommandRunner`, writes back |
| `Kodo.Core.ShellParser` | 300-line NimbleParsec grammar; supports quotes, escapes, ops |

6. Notable implementation details / "clever bits"
-------------------------------------------------

• **NimbleParsec grammar** – avoids negative-class ranges ([:not]) for safety; converts to rich
  execution plan allowing future advanced features (sub-shells, substitutions, etc.).

• **Command runner dual-path** – maintains backward compatibility (`CommandParser.to_simple/1`)
  so legacy tests and simple commands still work even while the new pipeline engine evolves.

• **Job IDs** – monotonic integer generation inside JobManager, ensuring sequential IDs across tests.

• **CommandMacro** – removes boilerplate; any adapter can do:

```elixir
use Kodo.Core.CommandMacro

defcommand "hello", description: "Say hi" do
  def execute([], _ctx), do: {:ok, "hi"}
end
```

• **VirtualFS wrappers** – search/stats/batch_rename demonstrate utility operations
  on top of a custom adapter without leaking adapter details to callers.

• **Telemetry attachment** – Application attaches four handler groups out-of-the-box so
  users get structured logs immediately while still being free to detach or redirect.

7. Test coverage hints
----------------------

`test/kodo/core/*_test.exs` exercises:

• Command parsing edge cases  
• Job lifecycle & control ops  
• VirtualFS server behaviours  
• Builtin vs external command precedence  

This gives confidence that the public contract is upheld and documents intended behaviour.

8. Future extension ideas (observed TODOs)
------------------------------------------

• Complete ExternalExecutor + proper PATH discovery  
• StdioManager: full duplex pipe handling, redirection to files  
• Control-operator semantics (short-circuit &&/||, sequences) in PipelineExecutor  
• Additional transports (SSH, WebSocket) and FS adapters (S3, memory)  
• Security sandboxing for external commands.

---

Kodo already offers a solid baseline for embedding a friendly, Elixir-powered shell with advanced
parsing, job control and telemetry.  Its clear separation via ports & adapters makes it easy to
extend in any direction your application requires.
