# Phase 6: Essential Built-in Commands

## Overview
Implement essential built-in commands that provide core file system operations and utilities, integrating seamlessly with the VFS system for cross-platform compatibility.

## Tasks

### 1. File Operations (`lib/kodo/commands/file_operations.ex`)

#### Core File Commands
```elixir
defmodule Kodo.Commands.FileOperations do
  use Kodo.Core.CommandMacro

  defcommand "cat" do
    @description "Display file contents"
    @usage "cat [OPTION]... [FILE]..."
    @meta [:builtin, :pure]
    
    def execute(args, context) do
      # Read and display file contents via VFS
      # Support multiple files
      # Handle binary files gracefully
      # Support options: -n (number lines), -b (number non-blank)
    end
  end

  defcommand "touch" do
    @description "Create empty files or update timestamps"
    @usage "touch [OPTION]... FILE..."
    @meta [:builtin]
    
    def execute(args, context) do
      # Create empty files if they don't exist
      # Update timestamps if they do exist
      # Support options: -c (no create), -t (specific time)
    end
  end

  defcommand "rm" do
    @description "Remove files and directories"
    @usage "rm [OPTION]... FILE..."
    @meta [:builtin]
    
    def execute(args, context) do
      # Remove files via VFS
      # Support options: -r (recursive), -f (force), -i (interactive)
      # Proper error handling for permission denied
      # Safety checks for important directories
    end
  end

  defcommand "mkdir" do
    @description "Create directories"
    @usage "mkdir [OPTION]... DIRECTORY..."
    @meta [:builtin]
    
    def execute(args, context) do
      # Create directories via VFS
      # Support options: -p (parents), -m (mode)
      # Handle existing directory case gracefully
    end
  end

  defcommand "rmdir" do
    @description "Remove empty directories"
    @usage "rmdir [OPTION]... DIRECTORY..."
    @meta [:builtin]
    
    def execute(args, context) do
      # Remove empty directories via VFS
      # Support options: -p (parents)
      # Error if directory not empty (unless forced)
    end
  end

  defcommand "cp" do
    @description "Copy files and directories"
    @usage "cp [OPTION]... SOURCE... DEST"
    @meta [:builtin]
    
    def execute(args, context) do
      # Copy files/directories via VFS
      # Support cross-filesystem copying
      # Support options: -r (recursive), -f (force), -i (interactive)
      # Preserve timestamps and permissions when possible
    end
  end

  defcommand "mv" do
    @description "Move/rename files and directories"
    @usage "mv [OPTION]... SOURCE... DEST"
    @meta [:builtin]
    
    def execute(args, context) do
      # Move/rename via VFS
      # Support cross-filesystem moves (copy + delete)
      # Support options: -f (force), -i (interactive)
      # Atomic operations when possible
    end
  end
end
```

### 2. Text Processing (`lib/kodo/commands/text_processing.ex`)

#### Text Utilities
```elixir
defmodule Kodo.Commands.TextProcessing do
  use Kodo.Core.CommandMacro

  defcommand "echo" do
    @description "Display text"
    @usage "echo [OPTION]... [STRING]..."
    @meta [:builtin, :pure]
    
    def execute(args, context) do
      # Output text to stdout
      # Support options: -n (no newline), -e (enable escapes)
      # Handle escape sequences: \n, \t, \r, \\, etc.
    end
  end

  defcommand "printf" do
    @description "Format and print text"
    @usage "printf FORMAT [ARGUMENT]..."
    @meta [:builtin, :pure]
    
    def execute(args, context) do
      # C-style printf formatting
      # Support format specifiers: %s, %d, %f, %x, etc.
      # Proper error handling for format mismatches
    end
  end

  defcommand "wc" do
    @description "Count lines, words, and characters"
    @usage "wc [OPTION]... [FILE]..."
    @meta [:builtin, :pure]
    
    def execute(args, context) do
      # Count lines, words, characters in files
      # Support options: -l (lines), -w (words), -c (chars), -m (chars with multibyte)
      # Read from stdin if no files specified
    end
  end

  defcommand "head" do
    @description "Display first lines of files"
    @usage "head [OPTION]... [FILE]..."
    @meta [:builtin, :pure]
    
    def execute(args, context) do
      # Show first N lines of files (default 10)
      # Support options: -n (number of lines), -c (number of bytes)
      # Handle multiple files with headers
    end
  end

  defcommand "tail" do
    @description "Display last lines of files"
    @usage "tail [OPTION]... [FILE]..."
    @meta [:builtin, :pure]
    
    def execute(args, context) do
      # Show last N lines of files (default 10)
      # Support options: -n (number of lines), -f (follow), -c (bytes)
      # Follow mode for log monitoring
    end
  end

  defcommand "grep" do
    @description "Search text patterns"
    @usage "grep [OPTION]... PATTERN [FILE]..."
    @meta [:builtin, :pure]
    
    def execute(args, context) do
      # Search for patterns in files
      # Support regex patterns
      # Support options: -i (ignore case), -v (invert), -n (line numbers)
      # -r (recursive), -l (files with matches), -c (count)
    end
  end

  defcommand "sort" do
    @description "Sort lines of text"
    @usage "sort [OPTION]... [FILE]..."
    @meta [:builtin, :pure]
    
    def execute(args, context) do
      # Sort lines alphabetically or numerically
      # Support options: -n (numeric), -r (reverse), -u (unique)
      # -k (key field), -t (field separator)
    end
  end

  defcommand "uniq" do
    @description "Remove duplicate lines"
    @usage "uniq [OPTION]... [INPUT [OUTPUT]]"
    @meta [:builtin, :pure]
    
    def execute(args, context) do
      # Remove or count duplicate consecutive lines
      # Support options: -c (count), -d (duplicates only), -u (unique only)
    end
  end
end
```

### 3. System Information (`lib/kodo/commands/system_info.ex`)

#### System Commands
```elixir
defmodule Kodo.Commands.SystemInfo do
  use Kodo.Core.CommandMacro

  defcommand "ps" do
    @description "Show running processes"
    @usage "ps [OPTION]..."
    @meta [:builtin, :pure]
    
    def execute(args, context) do
      # Show process information
      # Support options: aux (all processes), -e (all), -f (full format)
      # Integration with Elixir process monitoring
    end
  end

  defcommand "who" do
    @description "Show logged in users"
    @usage "who [OPTION]..."
    @meta [:builtin, :pure]
    
    def execute(args, context) do
      # Show current shell sessions
      # Integration with Kodo session management
    end
  end

  defcommand "date" do
    @description "Display or set date"
    @usage "date [OPTION]... [+FORMAT]"
    @meta [:builtin, :pure]
    
    def execute(args, context) do
      # Display current date/time
      # Support format strings: +%Y-%m-%d, +%H:%M:%S, etc.
      # UTC and timezone support
    end
  end

  defcommand "uptime" do
    @description "Show system uptime"
    @usage "uptime"
    @meta [:builtin, :pure]
    
    def execute(_args, context) do
      # Show Elixir VM uptime and load
      # Integration with :erlang.statistics()
    end
  end

  defcommand "df" do
    @description "Show filesystem disk space usage"
    @usage "df [OPTION]... [FILE]..."
    @meta [:builtin, :pure]
    
    def execute(args, context) do
      # Show VFS mount point usage
      # Support options: -h (human readable), -T (filesystem type)
    end
  end

  defcommand "du" do
    @description "Show directory space usage"
    @usage "du [OPTION]... [FILE]..."
    @meta [:builtin, :pure]
    
    def execute(args, context) do
      # Calculate directory sizes via VFS
      # Support options: -h (human readable), -s (summary), -a (all files)
    end
  end
end
```

### 4. Utility Commands (`lib/kodo/commands/utilities.ex`)

#### General Utilities
```elixir
defmodule Kodo.Commands.Utilities do
  use Kodo.Core.CommandMacro

  defcommand "true" do
    @description "Return successful exit status"
    @usage "true"
    @meta [:builtin, :pure]
    
    def execute(_args, _context) do
      {:ok, "", 0}
    end
  end

  defcommand "false" do
    @description "Return unsuccessful exit status"
    @usage "false"
    @meta [:builtin, :pure]
    
    def execute(_args, _context) do
      {:error, "", 1}
    end
  end

  defcommand "test" do
    @description "Evaluate conditional expressions"
    @usage "test EXPRESSION"
    @meta [:builtin, :pure]
    
    def execute(args, context) do
      # File tests: -f (file), -d (directory), -r (readable), -w (writable)
      # String tests: -z (zero length), -n (non-zero length)
      # Numeric tests: -eq, -ne, -lt, -le, -gt, -ge
      # Boolean operators: -a (and), -o (or), ! (not)
    end
  end

  defcommand "[" do
    @description "Evaluate conditional expressions (alias for test)"
    @usage "[ EXPRESSION ]"
    @meta [:builtin, :pure]
    
    def execute(args, context) do
      # Same as test command but expects closing ]
      # Validate that last argument is ]
    end
  end

  defcommand "which" do
    @description "Locate command"
    @usage "which [-a] command..."
    @meta [:builtin, :pure]
    
    def execute(args, context) do
      # Find command in PATH or builtin registry
      # Support options: -a (all matches)
      # Check builtins first, then external commands
    end
  end

  defcommand "type" do
    @description "Display command type"
    @usage "type [-t] command..."
    @meta [:builtin, :pure]
    
    def execute(args, context) do
      # Show if command is builtin, alias, function, or external
      # Support options: -t (type only), -p (path only)
    end
  end

  defcommand "sleep" do
    @description "Delay for specified time"
    @usage "sleep NUMBER[SUFFIX]..."
    @meta [:builtin]
    
    def execute(args, context) do
      # Sleep for specified duration
      # Support suffixes: s (seconds), m (minutes), h (hours)
    end
  end

  defcommand "basename" do
    @description "Strip directory and suffix from filenames"
    @usage "basename NAME [SUFFIX]"
    @meta [:builtin, :pure]
    
    def execute(args, context) do
      # Extract filename from path
      # Optionally remove suffix
    end
  end

  defcommand "dirname" do
    @description "Strip last component from file name"
    @usage "dirname NAME..."
    @meta [:builtin, :pure]
    
    def execute(args, context) do
      # Extract directory from path
    end
  end
end
```

### 5. Directory Navigation (`lib/kodo/commands/navigation.ex`)

#### Enhanced Navigation
```elixir
defmodule Kodo.Commands.Navigation do
  use Kodo.Core.CommandMacro

  defcommand "pushd" do
    @description "Push directory onto stack"
    @usage "pushd [dir]"
    @meta [:builtin, :changes_dir]
    
    def execute(args, context) do
      # Push current directory onto stack
      # Change to new directory
      # Store stack in session state
    end
  end

  defcommand "popd" do
    @description "Pop directory from stack"
    @usage "popd [+n]"
    @meta [:builtin, :changes_dir]
    
    def execute(args, context) do
      # Pop directory from stack and cd to it
      # Support numeric argument for specific stack position
    end
  end

  defcommand "dirs" do
    @description "Display directory stack"
    @usage "dirs [-clpv]"
    @meta [:builtin, :pure]
    
    def execute(args, context) do
      # Show current directory stack
      # Support options: -c (clear), -l (long format), -p (one per line), -v (verbose)
    end
  end

  defcommand "find" do
    @description "Search for files and directories"
    @usage "find [PATH...] [EXPRESSION]"
    @meta [:builtin, :pure]
    
    def execute(args, context) do
      # Search filesystem via VFS
      # Support expressions: -name, -type, -size, -mtime
      # Actions: -print, -exec, -delete
    end
  end
end
```

### 6. VFS Integration (`lib/kodo/core/vfs_commands.ex`)

#### VFS-Specific Operations
```elixir
defmodule Kodo.Core.VFSCommands do
  use Kodo.Core.CommandMacro

  defcommand "mount" do
    @description "Mount filesystem"
    @usage "mount [OPTION]... SOURCE TARGET"
    @meta [:builtin]
    
    def execute(args, context) do
      # Mount new filesystem adapter at target path
      # Support different adapter types
      # Update VFS manager with new mount
    end
  end

  defcommand "umount" do
    @description "Unmount filesystem"
    @usage "umount TARGET"
    @meta [:builtin]
    
    def execute(args, context) do
      # Unmount filesystem at target path
      # Handle open files and graceful cleanup
    end
  end

  defcommand "vfsinfo" do
    @description "Show VFS information"
    @usage "vfsinfo [PATH]"
    @meta [:builtin, :pure]
    
    def execute(args, context) do
      # Show VFS mount points and adapter information
      # Display filesystem statistics
    end
  end
end
```

### 7. Command Option Parsing (`lib/kodo/core/option_parser.ex`)

#### Enhanced Option Parsing
```elixir
defmodule Kodo.Core.OptionParser do
  # Parse command options with full GNU-style support
  def parse(args, option_spec)
  
  # Support short options: -a, -b, -c
  def parse_short_options(args, spec)
  
  # Support long options: --verbose, --output=file
  def parse_long_options(args, spec)
  
  # Support combined short options: -abc = -a -b -c
  def parse_combined_options(args, spec)
  
  # Support option arguments: -f file, --file=name
  def parse_option_arguments(args, spec)
  
  # Support -- to end option parsing
  def parse_with_terminator(args, spec)
  
  # Generate help text from option spec
  def generate_help(option_spec, usage)
end
```

### 8. Error Handling and User Feedback

#### Consistent Error Messages
```elixir
defmodule Kodo.Commands.ErrorHandler do
  # Standard error message formatting
  def format_error(command, error_type, details)
  
  # File not found errors
  def file_not_found_error(command, filename)
  
  # Permission denied errors
  def permission_denied_error(command, filename)
  
  # Invalid option errors
  def invalid_option_error(command, option)
  
  # Usage information
  def show_usage(command, usage_string)
  
  # Help text generation
  def generate_help_text(command_module)
end
```

### 9. Testing (`test/kodo/commands/`)

#### File Operations Tests (`file_operations_test.exs`)
```elixir
test "cat displays file contents" do
  # Setup test file in VFS
  result = execute_command("cat test.txt", context)
  assert {:ok, content, 0} = result
  assert content == "test file content"
end

test "cp copies files correctly" do
  result = execute_command("cp source.txt dest.txt", context)
  assert {:ok, "", 0} = result
  # Verify file was copied via VFS
end

test "rm removes files" do
  result = execute_command("rm test.txt", context)
  assert {:ok, "", 0} = result
  # Verify file was removed
end
```

#### Text Processing Tests (`text_processing_test.exs`)
```elixir
test "echo outputs text" do
  result = execute_command("echo hello world", context)
  assert {:ok, "hello world\n", 0} = result
end

test "grep finds patterns" do
  result = execute_command("grep pattern test.txt", context)
  assert {:ok, output, 0} = result
  assert String.contains?(output, "pattern")
end
```

#### Integration Tests (`builtin_integration_test.exs`)
```elixir
test "file operations work together" do
  # Create file, copy it, list directory, remove files
  execute_command("touch test.txt", context)
  execute_command("cp test.txt backup.txt", context)
  result = execute_command("ls", context)
  assert String.contains?(result, "test.txt")
  assert String.contains?(result, "backup.txt")
end
```

### 10. Performance Optimization

#### Efficient File Operations
- Stream large files instead of loading into memory
- Async I/O for file operations when possible
- Efficient pattern matching for grep
- Optimized directory traversal for find

#### Memory Management
- Lazy evaluation for large datasets
- Proper cleanup of file handles
- Efficient string building for output
- Memory-mapped files for large operations

## Success Criteria
- [ ] All essential file operations work via VFS
- [ ] Text processing commands handle various input types
- [ ] System information commands provide useful data
- [ ] Utility commands match standard behavior
- [ ] Enhanced navigation with directory stack
- [ ] Proper error handling and user feedback
- [ ] GNU-style option parsing support
- [ ] Cross-platform compatibility via VFS
- [ ] All tests pass with >90% coverage
- [ ] Performance suitable for large files/directories

## Example Usage
```elixir
# File operations
iex> Kodo.Shell.eval(session, "touch newfile.txt")
{:ok, ""}
iex> Kodo.Shell.eval(session, "echo 'Hello World' > newfile.txt")
{:ok, ""}
iex> Kodo.Shell.eval(session, "cat newfile.txt")
{:ok, "Hello World\n"}

# Text processing  
iex> Kodo.Shell.eval(session, "cat data.txt | grep important | sort")
{:ok, "important line 1\nimportant line 2\n"}

# Directory navigation
iex> Kodo.Shell.eval(session, "pushd /tmp")
{:ok, "/tmp ~/project"}
iex> Kodo.Shell.eval(session, "popd")
{:ok, "~/project"}
```

## Dependencies
- Enhanced VFS integration
- Existing `Kodo.Core` modules
- Option parsing library (or custom implementation)

## Estimated Time
2-3 weeks for implementation and testing
