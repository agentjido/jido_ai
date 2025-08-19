# Phase 7: Scripting Support & Exit Status Handling

## Overview
Add comprehensive scripting support allowing Kodo to execute script files, handle exit statuses properly, and provide a complete shell scripting environment.

## Tasks

### 1. Script Execution Engine (`lib/kodo/core/script_executor.ex`)

#### Script Runner
```elixir
defmodule Kodo.Core.ScriptExecutor do
  # Execute script file line by line
  def execute_script(script_path, args, context)
  
  # Execute script content from string
  def execute_script_content(content, args, context)
  
  # Handle script arguments ($0, $1, $2, ...)
  def setup_script_args(args, context)
  
  # Execute single script line with proper context
  def execute_line(line, line_number, context)
  
  # Handle script errors and early termination
  def handle_script_error(error, line_number, context)
  
  # Cleanup script execution context
  def cleanup_script_context(context)
end
```

#### Script Context
```elixir
defmodule Kodo.Core.ScriptContext do
  defstruct [
    :script_path,        # Path to script file
    :script_args,        # Script arguments ($0, $1, ...)
    :line_number,        # Current line number
    :exit_on_error,      # Exit script on any error (set -e)
    :trace_execution,    # Trace commands before execution (set -x)
    :unset_vars_error,   # Error on unset variables (set -u)
    :parent_context,     # Parent shell context
    :script_vars,        # Script-local variables
    :return_value        # Script return value
  ]
end
```

### 2. Enhanced Exit Status System (`lib/kodo/core/exit_status.ex`)

#### Exit Status Management
```elixir
defmodule Kodo.Core.ExitStatus do
  # Track exit status in session
  def set_exit_status(session_id, status)
  def get_exit_status(session_id)
  
  # Standard exit status codes
  def success(), do: 0
  def general_error(), do: 1
  def misuse_of_builtin(), do: 2
  def command_not_found(), do: 127
  def command_not_executable(), do: 126
  def signal_termination(signal), do: 128 + signal
  
  # Exit status for control flow
  def should_continue_and?(status), do: status == 0
  def should_continue_or?(status), do: status != 0
  
  # Convert Elixir results to exit status
  def from_result({:ok, _output}), do: 0
  def from_result({:error, _reason}), do: 1
  def from_result({:exit, status}), do: status
end
```

#### Exit Command
```elixir
defcommand "exit" do
  @description "Exit the shell"
  @usage "exit [STATUS]"
  @meta [:builtin]
  
  def execute(args, context) do
    status = case args do
      [] -> get_last_exit_status(context)
      [status_str] -> String.to_integer(status_str)
    end
    
    {:exit, status}
  end
end
```

### 3. Script File Detection and Execution

#### File Association
```elixir
defmodule Kodo.Core.FileExecutor do
  # Determine if file is executable script
  def executable?(file_path, context)
  
  # Check for shebang line
  def has_shebang?(file_path)
  
  # Execute file based on type
  def execute_file(file_path, args, context)
  
  # Handle different script types
  def execute_kodo_script(file_path, args, context)
  def execute_shebang_script(file_path, args, context)
end
```

#### Shebang Support
```bash
#!/usr/bin/env kodo
# Kodo shell script

echo "Hello from Kodo script!"
export VAR="script variable"
ls -la | grep .ex
```

### 4. Script Control Flow (`lib/kodo/core/control_flow.ex`)

#### Control Flow Statements
```elixir
defmodule Kodo.Core.ControlFlow do
  # Conditional execution
  def execute_if_statement(condition, then_block, else_block, context)
  
  # Loop constructs
  def execute_for_loop(var, values, body, context)
  def execute_while_loop(condition, body, context)
  
  # Function definitions and calls
  def define_function(name, params, body, context)
  def call_function(name, args, context)
  
  # Early returns and breaks
  def handle_return(value, context)
  def handle_break(context)
  def handle_continue(context)
end
```

#### Extended Script Syntax (Future Enhancement)
```bash
# Conditional statements
if test -f "file.txt"; then
    echo "File exists"
else
    echo "File not found"
fi

# For loops
for file in *.ex; do
    echo "Processing $file"
    cat "$file" | wc -l
done

# While loops
counter=0
while test $counter -lt 10; do
    echo "Count: $counter"
    counter=$((counter + 1))
done

# Functions
greet() {
    echo "Hello, $1!"
    return 0
}

greet "World"
```

### 5. Script Variable Scoping (`lib/kodo/core/variable_scope.ex`)

#### Variable Scope Management
```elixir
defmodule Kodo.Core.VariableScope do
  # Create new scope for script/function
  def push_scope(context)
  def pop_scope(context)
  
  # Variable assignment with scope awareness
  def set_variable(name, value, scope_type, context)
  def get_variable(name, context)
  
  # Export variables to parent scope
  def export_variable(name, context)
  
  # Local vs global variable handling
  def set_local(name, value, context)
  def set_global(name, value, context)
end
```

#### Variable Types
- **Global**: Available across all scripts and sessions
- **Local**: Limited to current script or function
- **Environment**: Exported to child processes
- **Special**: Read-only system variables ($?, $$, etc.)

### 6. Script Error Handling (`lib/kodo/core/script_error.ex`)

#### Error Handling Modes
```elixir
defmodule Kodo.Core.ScriptError do
  # Set script execution options
  def set_errexit(enabled, context)     # set -e / set +e
  def set_nounset(enabled, context)     # set -u / set +u
  def set_xtrace(enabled, context)      # set -x / set +x
  def set_pipefail(enabled, context)    # set -o pipefail
  
  # Handle different error conditions
  def handle_command_failure(command, exit_status, context)
  def handle_unset_variable(var_name, context)
  def handle_syntax_error(line, line_number, context)
  
  # Error reporting
  def format_script_error(error, script_path, line_number)
  def print_error_context(script_content, line_number)
end
```

#### Set Command for Script Options
```elixir
defcommand "set" do
  @description "Set shell options"
  @usage "set [-+abefhkmnptuvxBCEHPT] [-o option] [arg ...]"
  @meta [:builtin]
  
  def execute(args, context) do
    # Parse and apply shell options
    # -e: Exit on error
    # -u: Error on unset variables
    # -x: Trace execution
    # -o pipefail: Fail on pipe errors
  end
end
```

### 7. Non-Interactive Mode (`lib/kodo/core/batch_mode.ex`)

#### Batch Execution
```elixir
defmodule Kodo.Core.BatchMode do
  # Execute Kodo in non-interactive mode
  def run_script(script_path, args)
  
  # Execute commands from stdin
  def run_stdin_commands()
  
  # Execute single command and exit
  def run_command(command, args)
  
  # Setup batch context (no prompt, different error handling)
  def setup_batch_context(opts)
end
```

#### Command Line Interface
```bash
# Execute script file
kodo script.kodo arg1 arg2

# Execute single command
kodo -c "ls -la | grep .ex"

# Read commands from stdin
echo "ls -la" | kodo

# Script with options
kodo -e -x script.kodo  # Exit on error, trace execution
```

### 8. Configuration Scripts (`lib/kodo/core/config_script.ex`)

#### Startup Scripts
```elixir
defmodule Kodo.Core.ConfigScript do
  # Execute user's .kodorc on startup
  def load_user_config(session_id)
  
  # Execute system-wide configuration
  def load_system_config()
  
  # Profile script execution (.kodo_profile)
  def load_profile_script(session_id)
  
  # Source command for loading scripts
  def source_script(script_path, context)
end
```

#### Source Command
```elixir
defcommand "source" do
  @description "Execute commands from file in current shell"
  @usage "source FILENAME [ARGUMENTS]"
  @meta [:builtin]
  
  def execute(args, context) do
    # Execute script in current context (not subshell)
    # Variables and functions affect current session
  end
end

# Alias for source
defcommand "." do
  @description "Execute commands from file in current shell"
  @usage ". FILENAME [ARGUMENTS]"
  @meta [:builtin]
  
  def execute(args, context) do
    # Same as source command
  end
end
```

### 9. Testing (`test/kodo/core/`)

#### Script Execution Tests (`script_executor_test.exs`)
```elixir
test "execute simple script" do
  script_content = """
  echo "Hello"
  echo "World"
  """
  
  result = ScriptExecutor.execute_script_content(script_content, [], context)
  assert {:ok, output, 0} = result
  assert output =~ "Hello"
  assert output =~ "World"
end

test "script arguments available as $0, $1, etc." do
  script_content = "echo $0 $1 $2"
  result = ScriptExecutor.execute_script_content(script_content, ["arg1", "arg2"], context)
  assert {:ok, output, 0} = result
  assert output =~ "script.kodo arg1 arg2"
end

test "exit status propagates correctly" do
  script_content = """
  false
  echo "This should not run"
  """
  
  context = %{context | script_options: %{exit_on_error: true}}
  result = ScriptExecutor.execute_script_content(script_content, [], context)
  assert {:error, _output, 1} = result
end
```

#### Exit Status Tests (`exit_status_test.exs`)
```elixir
test "exit status tracked per session" do
  ExitStatus.set_exit_status(session_id, 42)
  assert ExitStatus.get_exit_status(session_id) == 42
end

test "control flow respects exit status" do
  assert ExitStatus.should_continue_and?(0) == true
  assert ExitStatus.should_continue_and?(1) == false
  assert ExitStatus.should_continue_or?(0) == false
  assert ExitStatus.should_continue_or?(1) == true
end
```

#### Integration Tests (`scripting_integration_test.exs`)
```elixir
test "full script execution with variables and functions" do
  script_content = """
  #!/usr/bin/env kodo
  
  # Set variables
  NAME="Kodo"
  VERSION="1.0"
  
  # Define function
  greet() {
      echo "Hello from $NAME version $VERSION"
      return 0
  }
  
  # Call function
  greet
  
  # Exit with success
  exit 0
  """
  
  result = execute_script_file(script_content, [])
  assert {:ok, output, 0} = result
  assert output =~ "Hello from Kodo version 1.0"
end
```

### 10. Performance and Optimization

#### Script Execution Performance
- Parse script once, execute multiple times for loops
- Efficient variable lookup with scope chains
- Lazy evaluation of conditional blocks
- Minimize string allocations during execution

#### Memory Management
- Clean up script contexts after execution
- Limit recursion depth for function calls
- Efficient storage of script variables and functions
- Garbage collection of unused script data

### 11. Integration with Existing Systems

#### Update Main Modules
- **CommandRunner**: Handle script file execution
- **SessionManager**: Track script contexts and variables
- **Shell**: Add batch mode and script execution APIs
- **Application**: Support command-line script execution

#### CLI Integration
```elixir
# Update main Kodo module for CLI usage
def main(args) do
  case args do
    [] -> start_interactive_shell()
    ["-c", command | _] -> execute_command_and_exit(command)
    [script_path | script_args] -> execute_script_and_exit(script_path, script_args)
    _ -> show_usage_and_exit()
  end
end
```

## Success Criteria
- [ ] Script files execute line by line correctly
- [ ] Exit status handling works for all commands
- [ ] Script arguments accessible as $0, $1, etc.
- [ ] Non-interactive mode for batch execution
- [ ] Shebang support for executable scripts
- [ ] Error handling modes (set -e, set -u, set -x)
- [ ] Source command loads scripts in current context
- [ ] Configuration scripts load on startup
- [ ] Variable scoping works correctly
- [ ] All tests pass with >90% coverage

## Example Usage
```bash
# Create script file
cat > hello.kodo << 'EOF'
#!/usr/bin/env kodo
echo "Hello, $1!"
echo "Current directory: $(pwd)"
ls -la | head -5
exit 0
EOF

# Make executable and run
chmod +x hello.kodo
./hello.kodo World

# Run with kodo command
kodo hello.kodo World

# Execute command directly
kodo -c "echo Hello && ls -la"

# Script with error handling
kodo -e -x hello.kodo World  # Exit on error, trace execution
```

## Dependencies
- Enhanced variable and context management
- Existing `Kodo.Core` modules
- File system integration via VFS

## Estimated Time
2-3 weeks for implementation and testing
