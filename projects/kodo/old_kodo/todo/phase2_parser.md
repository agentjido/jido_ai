# Phase 2: Robust Parser with NimbleParsec

## Overview
Replace the simple tokenizer with a robust NimbleParsec-based grammar that supports pipes, redirections, and control operators to generate execution plan ASTs.

## Tasks

### 1. Add Dependencies
- Add `nimble_parsec` dependency to `mix.exs`
- Run `mix deps.get` to install

### 2. Create Shell Parser (`lib/kodo/core/shell_parser.ex`)
Build NimbleParsec grammar with support for:

#### Tokens
- **Plain tokens**: `word`, `path`, unquoted strings
- **Quoted strings**: 
  - Single quotes: `'literal string'` (no interpolation)
  - Double quotes: `"string with $vars"` (with interpolation)
- **Escaped characters**: `\$`, `\"`, `\\`, etc.
- **Special characters**: `|`, `>`, `>>`, `<`, `&&`, `||`, `;`, `&`

#### Grammar Structure
```
command_line := pipeline (control_op pipeline)*
pipeline := command ("|" command)*
command := token+ redirection*
redirection := (">" | ">>" | "<") token
control_op := "&&" | "||" | ";" | "&"
token := quoted_string | escaped_char | plain_token
```

#### Parser Functions
- `parse_command_line/1` - Main entry point
- `parse_pipeline/1` - Parse pipe sequences
- `parse_command/1` - Parse individual commands
- `parse_token/1` - Parse individual tokens

### 3. Create Execution Plan Structs (`lib/kodo/core/execution_plan.ex`)

#### ExecutionPlan
```elixir
defmodule Kodo.Core.ExecutionPlan do
  defstruct [
    :pipelines,     # List of Pipeline structs
    :control_ops    # List of control operators between pipelines
  ]
end
```

#### Pipeline
```elixir
defmodule Kodo.Core.Pipeline do
  defstruct [
    :commands,      # List of Command structs
    :background?    # Boolean - run in background (&)
  ]
end
```

#### Command
```elixir
defmodule Kodo.Core.Command do
  defstruct [
    :name,          # Command name
    :args,          # List of arguments
    :redirections,  # List of Redirection structs
    :env            # Environment variables for this command
  ]
end
```

#### Redirection
```elixir
defmodule Kodo.Core.Redirection do
  defstruct [
    :type,          # :input, :output, :append
    :target         # File path or file descriptor
  ]
end
```

### 4. Update Command Parser (`lib/kodo/core/command_parser.ex`)
- Replace current tokenization with `ShellParser.parse_command_line/1`
- Convert parsed AST to `ExecutionPlan` struct
- Maintain backward compatibility for simple commands
- Add error handling for malformed syntax

### 5. Test Cases (`test/kodo/core/shell_parser_test.exs`)

#### Basic Commands
- `"ls -la"` → Simple command with args
- `"echo hello"` → Command with argument

#### Quoted Strings
- `'echo "hello world"'` → Single quotes preserving double quotes
- `"echo 'hello world'"` → Double quotes preserving single quotes
- `"echo \"escaped quotes\""` → Escaped quotes

#### Pipes
- `"ls | grep txt"` → Simple pipe
- `"cat file.txt | grep pattern | wc -l"` → Multiple pipes

#### Redirections
- `"echo hello > output.txt"` → Output redirection
- `"cat >> log.txt"` → Append redirection
- `"grep pattern < input.txt"` → Input redirection
- `"cmd 2>&1 > output.txt"` → Complex redirection (future)

#### Control Operators
- `"make && make test"` → AND operator
- `"rm file.txt || echo 'failed'"` → OR operator
- `"cmd1; cmd2; cmd3"` → Sequential execution
- `"long_process &"` → Background execution

#### Complex Examples
- `'echo "a | b" | grep x > f.txt'` → Quoted pipes in output redirection
- `"find . -name '*.ex' | xargs grep -l 'defmodule'"` → File pattern matching
- `"export VAR=value && echo $VAR"` → Variable assignment and usage

#### Error Cases
- Unclosed quotes: `"echo 'unclosed`
- Invalid redirections: `"> > file.txt"`
- Malformed pipes: `"cmd |"`
- Invalid control operators: `"cmd &&&"`

### 6. Integration Tests (`test/kodo/core/execution_plan_test.exs`)
- Test AST generation from various command patterns
- Verify proper struct nesting and relationships
- Test error propagation and recovery

### 7. Performance Tests
- Benchmark parsing speed on complex command lines
- Memory usage profiling for large ASTs
- Stress test with deeply nested structures

## Success Criteria
- [ ] All existing simple commands continue to work
- [ ] Complex shell syntax parses correctly to AST
- [ ] Error handling provides helpful messages
- [ ] All tests pass (target: 95%+ coverage)
- [ ] Parser handles edge cases gracefully
- [ ] Performance acceptable for interactive use

## Example Usage
```elixir
# Simple command
iex> ShellParser.parse_command_line("ls -la")
{:ok, %ExecutionPlan{
  pipelines: [
    %Pipeline{
      commands: [
        %Command{name: "ls", args: ["-la"], redirections: []}
      ],
      background?: false
    }
  ],
  control_ops: []
}}

# Complex pipeline
iex> ShellParser.parse_command_line("find . -name '*.ex' | grep -v test | head -10 > results.txt")
{:ok, %ExecutionPlan{...}}
```

## Dependencies
- `nimble_parsec` ~> 1.4
- Existing `Kodo.Core` modules

## Estimated Time
2-3 weeks for full implementation and testing
