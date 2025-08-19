# Phase 4: Shell Language Features

## Overview
Implement core shell language features including variable expansion, globbing, command substitution, aliases, and functions to provide a complete shell experience.

## Tasks

### 1. Variable Expansion (`lib/kodo/core/variable_expander.ex`)

#### Environment Variable Expansion
- `$VAR` and `${VAR}` expansion from session environment
- Special variables:
  - `$?` → Exit status of last command
  - `$$` → Current shell process ID  
  - `$!` → Process ID of last background job
  - `$HOME` → User home directory
  - `$PWD` → Current working directory
  - `$PATH` → Command search path
  - `$0, $1, $2...` → Script arguments (future)

#### Variable Expansion Rules
```elixir
defmodule Kodo.Core.VariableExpander do
  # Main expansion function
  def expand(text, context)
  
  # Expand single variable reference
  def expand_variable(var_name, context)
  
  # Handle special variables ($?, $$, $!, etc.)
  def expand_special_variable(special_var, context)
  
  # Expand with default values ${VAR:-default}
  def expand_with_default(var_name, default_value, context)
  
  # Expand with error if unset ${VAR:?error_message}
  def expand_with_error(var_name, error_message, context)
end
```

#### Variable Assignment Commands
```elixir
defcommand "export" do
  @description "Set environment variable"
  @usage "export VAR=value"
  @meta [:builtin]
  
  def execute(args, context) do
    # Parse VAR=value and set in session environment
  end
end

defcommand "unset" do
  @description "Remove environment variable"
  @usage "unset VAR [VAR2...]"
  @meta [:builtin]
  
  def execute(args, context) do
    # Remove variables from session environment
  end
end
```

### 2. Globbing Support (`lib/kodo/core/glob_expander.ex`)

#### Pattern Matching via VFS
- `*` → Match any characters except path separator
- `?` → Match any single character
- `[abc]` → Match any character in brackets
- `[a-z]` → Match any character in range
- `[!abc]` → Match any character NOT in brackets
- `**` → Recursive directory matching (future)

#### Glob Implementation
```elixir
defmodule Kodo.Core.GlobExpander do
  # Expand glob patterns in command arguments
  def expand_globs(args, context)
  
  # Expand single glob pattern using VFS
  def expand_pattern(pattern, context)
  
  # Convert shell glob to Elixir regex
  def glob_to_regex(pattern)
  
  # Match pattern against VFS directory contents
  def match_in_directory(pattern, dir_path, vfs_manager)
end
```

#### VFS Integration
- Use `VFS.Manager` to list directory contents
- Respect mounted filesystems and virtual paths
- Handle cross-filesystem glob expansion
- Proper error handling for inaccessible directories

### 3. Command Substitution (`lib/kodo/core/command_substitution.ex`)

#### Substitution Syntax
- `$(command)` → Modern command substitution
- `` `command` `` → Traditional backtick substitution
- Nested substitution support: `$(echo $(date))`

#### Implementation
```elixir
defmodule Kodo.Core.CommandSubstitution do
  # Find and expand all command substitutions in text
  def expand_substitutions(text, context)
  
  # Execute command and capture output
  def execute_and_capture(command, context)
  
  # Handle nested substitutions recursively
  def expand_nested(text, context, depth \\ 0)
  
  # Parse substitution boundaries correctly
  def find_substitution_bounds(text, start_pos)
end
```

#### Output Processing
- Capture stdout from substituted commands
- Strip trailing newlines from output
- Handle multi-line output properly
- Error handling for failed substitutions

### 4. Aliases (`lib/kodo/core/alias_manager.ex`)

#### Alias Management
```elixir
defmodule Kodo.Core.AliasManager do
  # Store aliases in ETS table per session
  use GenServer
  
  def start_link(session_id)
  def set_alias(session_id, name, value)
  def get_alias(session_id, name)
  def remove_alias(session_id, name)
  def list_aliases(session_id)
  def expand_aliases(command_line, session_id)
end
```

#### Alias Commands
```elixir
defcommand "alias" do
  @description "Create or list aliases"
  @usage "alias [name[=value]]"
  @meta [:builtin]
  
  def execute(args, context) do
    case args do
      [] -> list_all_aliases(context)
      [name] -> show_alias(name, context)
      [assignment] -> set_alias(assignment, context)
    end
  end
end

defcommand "unalias" do
  @description "Remove aliases"
  @usage "unalias name [name2...]"
  @meta [:builtin]
  
  def execute(args, context) do
    # Remove specified aliases
  end
end
```

#### Alias Expansion Rules
- Expand only the first word of command line
- Prevent recursive alias expansion
- Support multi-word alias values
- Preserve argument quoting after expansion

### 5. Functions (`lib/kodo/core/function_manager.ex`)

#### Simple Shell Functions
```bash
# Function definition syntax
function_name() {
    command1
    command2
    return $?
}
```

#### Function Implementation
```elixir
defmodule Kodo.Core.FunctionManager do
  # Store function definitions per session
  use GenServer
  
  def start_link(session_id)
  def define_function(session_id, name, body)
  def call_function(session_id, name, args, context)
  def remove_function(session_id, name)
  def list_functions(session_id)
end

defmodule Kodo.Core.Function do
  defstruct [
    :name,
    :body,          # List of command strings
    :defined_at     # DateTime
  ]
end
```

### 6. Enhanced Command Parser Integration

#### Update Parser for Language Features
```elixir
defmodule Kodo.Core.LanguageProcessor do
  # Process command line through all language features
  def process_command_line(command_line, context) do
    command_line
    |> expand_aliases(context)
    |> expand_variables(context)  
    |> expand_command_substitutions(context)
    |> expand_globs(context)
    |> validate_syntax()
  end
  
  # Coordinate all expansion phases
  def expand_all(text, context)
  
  # Handle expansion errors gracefully
  def handle_expansion_error(error, context)
end
```

### 7. Quote Handling (`lib/kodo/core/quote_processor.ex`)

#### Quote Processing Rules
- Single quotes: Preserve everything literally (no expansion)
- Double quotes: Allow variable and command substitution
- Escape sequences: Handle `\"`, `\$`, `\\`, `\n`, etc.
- Quote removal after processing

#### Implementation
```elixir
defmodule Kodo.Core.QuoteProcessor do
  # Remove outer quotes and process contents
  def process_quotes(token, context)
  
  # Handle escape sequences
  def process_escapes(text)
  
  # Determine if token needs quote processing
  def quoted?(token)
  
  # Split text respecting quote boundaries
  def smart_split(text)
end
```

### 8. Testing (`test/kodo/core/`)

#### Variable Expansion Tests (`variable_expander_test.exs`)
```elixir
test "basic variable expansion" do
  context = %{env: %{"HOME" => "/home/user"}}
  assert VariableExpander.expand("$HOME/docs", context) == "/home/user/docs"
end

test "special variable expansion" do
  context = %{last_exit_status: 1}
  assert VariableExpander.expand("echo $?", context) == "echo 1"
end

test "default value expansion" do
  context = %{env: %{}}
  assert VariableExpander.expand("${MISSING:-default}", context) == "default"
end
```

#### Glob Expansion Tests (`glob_expander_test.exs`)
```elixir
test "simple glob expansion" do
  # Setup VFS with test files
  context = setup_test_filesystem()
  result = GlobExpander.expand_pattern("*.ex", context)
  assert "test.ex" in result
  assert "main.ex" in result
end

test "character class glob" do
  result = GlobExpander.expand_pattern("file[0-9].txt", context)
  assert "file1.txt" in result
  refute "filea.txt" in result
end
```

#### Command Substitution Tests (`command_substitution_test.exs`)
```elixir
test "basic command substitution" do
  result = CommandSubstitution.expand("echo $(echo hello)", context)
  assert result == "echo hello"
end

test "nested command substitution" do
  result = CommandSubstitution.expand("$(echo $(echo nested))", context)
  assert result == "nested"
end
```

#### Integration Tests (`language_features_integration_test.exs`)
```elixir
test "combined expansion features" do
  # Test command with variables, globs, and substitution
  command = "echo $HOME/*.ex $(date +%Y)"
  result = process_full_command(command, context)
  # Verify all expansions worked correctly
end
```

### 9. Performance Optimization

#### Caching Strategies
- Cache compiled glob patterns
- Memoize variable lookups within command
- Efficient alias resolution
- Lazy expansion for unused substitutions

#### Memory Management
- Limit recursion depth for substitutions
- Clean up temporary expansion state
- Efficient string building for large expansions

### 10. Error Handling

#### Graceful Degradation
- Continue execution on non-critical expansion failures
- Provide helpful error messages for syntax errors
- Fallback to literal strings for failed expansions
- User-configurable error handling modes

#### Error Types
```elixir
defmodule Kodo.Core.ExpansionError do
  defexception [:message, :type, :context]
  
  # Error types
  @types [:undefined_variable, :invalid_glob, :substitution_failed, 
          :recursive_alias, :syntax_error]
end
```

## Success Criteria
- [ ] Variable expansion works for all supported syntax
- [ ] Glob patterns expand correctly via VFS
- [ ] Command substitution handles nested cases
- [ ] Aliases expand properly without recursion
- [ ] Simple functions can be defined and called
- [ ] Quote processing preserves/expands appropriately
- [ ] Error handling provides helpful messages
- [ ] Performance suitable for interactive use
- [ ] All tests pass with >90% coverage

## Example Usage
```elixir
# Variable expansion
iex> Kodo.Shell.eval(session, "echo $HOME")
{:ok, "/home/user"}

# Glob expansion  
iex> Kodo.Shell.eval(session, "ls *.ex")
{:ok, "main.ex test.ex util.ex"}

# Command substitution
iex> Kodo.Shell.eval(session, "echo Today is $(date)")
{:ok, "Today is Mon Jan 15 10:30:00 2024"}

# Alias usage
iex> Kodo.Shell.eval(session, "alias ll='ls -la'")
{:ok, ""}
iex> Kodo.Shell.eval(session, "ll")
{:ok, "total 8\ndrwxr-xr-x..."}
```

## Dependencies
- Existing `Kodo.Core` modules
- Enhanced VFS integration
- Session state management

## Estimated Time
2-3 weeks for implementation and testing
