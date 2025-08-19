# Kodo Shell Development Plan

This directory contains detailed implementation plans for building Kodo into a full-featured native Elixir shell. Each phase builds upon the previous ones to create a complete shell environment comparable to Bash or Zsh.

## Completed Phases

- ✅ **Phase 0**: Project restructure and facade creation
- ✅ **Phase 1**: Command subsystem hardening with BuiltinExecutor and ExternalExecutor

## Remaining Implementation Phases

### [Phase 2: Robust Parser](./phase2_parser.md)
**Duration**: 2-3 weeks  
**Status**: Ready for implementation

Replace the simple tokenizer with a robust NimbleParsec-based grammar supporting:
- Complex shell syntax (pipes, redirections, control operators)
- Quoted strings with proper escaping
- Execution plan AST generation
- Error handling for malformed syntax

**Key Deliverables**:
- `ShellParser` module with NimbleParsec grammar
- `ExecutionPlan` structs for AST representation
- Comprehensive test suite for complex shell syntax

### [Phase 3: Job Control & Pipeline Execution](./phase3_job_control.md)
**Duration**: 2-3 weeks  
**Status**: Blocked by Phase 2

Implement job management and pipeline execution engine:
- JobManager for background process tracking
- Pipeline execution with proper stdio handling
- Job control commands (jobs, fg, bg, kill)
- Signal handling (Ctrl+C, Ctrl+Z)

**Key Deliverables**:
- `JobManager` GenServer for job lifecycle
- `PipelineExecutor` for command pipeline execution
- Job control built-in commands
- Signal handling and process management

### [Phase 4: Shell Language Features](./phase4_shell_features.md)
**Duration**: 2-3 weeks  
**Status**: Blocked by Phase 2

Core shell language features:
- Variable expansion ($VAR, ${VAR}, special variables)
- Globbing support (*, ?, [...]) via VFS
- Command substitution ($(cmd), backticks)
- Aliases and simple functions

**Key Deliverables**:
- `VariableExpander` for environment variable handling
- `GlobExpander` integrated with VFS
- `CommandSubstitution` with nested support
- `AliasManager` and `FunctionManager`

### [Phase 5: User Experience](./phase5_ux.md)
**Duration**: 2-3 weeks  
**Status**: Blocked by Phase 4

Modern shell user experience:
- Line editing with Emacs-style key bindings
- Command history with persistence and search
- Tab completion for commands, files, and variables
- Customizable prompts with color support

**Key Deliverables**:
- `LineEditor` with full editing capabilities
- `HistoryManager` with persistent storage
- `CompletionEngine` for intelligent tab completion
- `PromptManager` for customizable prompts

### [Phase 6: Essential Built-ins](./phase6_builtins.md)
**Duration**: 2-3 weeks  
**Status**: Blocked by Phase 5

Essential file and text processing commands:
- File operations (cat, touch, rm, mkdir, cp, mv)
- Text processing (echo, printf, grep, sort, wc)
- System information (ps, date, uptime, df)
- Enhanced navigation (pushd, popd, find)

**Key Deliverables**:
- Complete set of file operation commands
- Text processing utilities
- System information commands
- VFS-integrated file operations

### [Phase 7: Scripting Support](./phase7_scripting.md)
**Duration**: 2-3 weeks  
**Status**: Blocked by Phase 6

Complete scripting environment:
- Script file execution with proper exit status handling
- Non-interactive batch mode
- Shebang support for executable scripts
- Script control flow and error handling

**Key Deliverables**:
- `ScriptExecutor` for file execution
- CLI interface for batch processing
- Exit status management system
- Script debugging and error reporting

### [Phase 8: Packaging & Distribution](./phase8_packaging.md)
**Duration**: 1-2 weeks  
**Status**: Blocked by Phase 7

Production-ready packaging and distribution:
- Mix release configuration
- Cross-platform binary generation
- Installation scripts and package manager integration
- Documentation and user manual

**Key Deliverables**:
- Production Mix release
- Cross-platform binaries via CI/CD
- Installation scripts for all platforms
- Complete documentation

## Timeline Overview

| Phase | Duration | Cumulative Time | Status |
|-------|----------|-----------------|---------|
| Phase 0 | Complete | - | ✅ Done |
| Phase 1 | Complete | - | ✅ Done |
| Phase 2 | 2-3 weeks | 2-3 weeks | 🟡 Ready |
| Phase 3 | 2-3 weeks | 4-6 weeks | ⏸️ Blocked |
| Phase 4 | 2-3 weeks | 6-9 weeks | ⏸️ Blocked |
| Phase 5 | 2-3 weeks | 8-12 weeks | ⏸️ Blocked |
| Phase 6 | 2-3 weeks | 10-15 weeks | ⏸️ Blocked |
| Phase 7 | 2-3 weeks | 12-18 weeks | ⏸️ Blocked |
| Phase 8 | 1-2 weeks | 13-20 weeks | ⏸️ Blocked |

**Total Estimated Time**: 3-5 months for complete implementation

## Implementation Strategy

### Sequential Dependencies
The phases are designed with clear dependencies:
- **Phase 2** (Parser) is foundational for all subsequent phases
- **Phase 3** (Job Control) requires the parser for pipeline execution
- **Phase 4** (Language Features) builds on job control for proper expansion
- **Phase 5** (UX) enhances the complete shell experience
- **Phase 6** (Built-ins) provides essential commands
- **Phase 7** (Scripting) creates a complete shell environment
- **Phase 8** (Packaging) prepares for distribution

### Parallel Development Opportunities
Some components can be developed in parallel:
- Documentation can be written alongside implementation
- Testing frameworks can be developed early
- Infrastructure setup (CI/CD) can be done early
- Design decisions for later phases can be made early

### Quality Assurance
Each phase includes:
- Comprehensive unit tests (target: >90% coverage)
- Integration tests with previous phases
- Performance benchmarking
- Documentation updates
- User experience validation

## Getting Started

1. **Start with Phase 2**: The parser is foundational for everything else
2. **Follow the detailed prompts**: Each phase has comprehensive implementation details
3. **Maintain test coverage**: Write tests as you implement features
4. **Update documentation**: Keep the main README and docs current
5. **Validate integration**: Ensure each phase works with existing code

## Project Structure After Completion

```
lib/kodo/
├── shell.ex                 # Main public facade
├── cli.ex                   # Command line interface
├── application.ex           # OTP application
├── transport/               # Different shell interfaces
│   ├── enhanced_iex.ex      # Enhanced IEx transport
│   └── line_editor.ex       # Line editing functionality
├── core/                    # Core shell functionality
│   ├── shell_parser.ex      # NimbleParsec shell grammar
│   ├── execution_plan.ex    # AST structures
│   ├── job_manager.ex       # Job control
│   ├── pipeline_executor.ex # Pipeline execution
│   ├── variable_expander.ex # Variable expansion
│   ├── glob_expander.ex     # Glob expansion
│   ├── command_substitution.ex # Command substitution
│   ├── alias_manager.ex     # Alias management
│   ├── function_manager.ex  # Function management
│   ├── history_manager.ex   # Command history
│   ├── completion_engine.ex # Tab completion
│   ├── prompt_manager.ex    # Prompt customization
│   ├── script_executor.ex   # Script execution
│   ├── exit_status.ex       # Exit status handling
│   └── ...                  # Other core modules
├── commands/                # Built-in commands
│   ├── file_operations.ex   # File commands
│   ├── text_processing.ex   # Text utilities
│   ├── system_info.ex       # System commands
│   ├── utilities.ex         # General utilities
│   ├── navigation.ex        # Directory navigation
│   └── job_control.ex       # Job control commands
└── ...
```

This structure provides a clear separation of concerns and makes the codebase maintainable as it grows to full shell functionality.
