# Phase 5: User Experience Enhancements

## Overview
Implement line editing, command history, tab completion, and customizable prompts to provide a modern, user-friendly shell experience comparable to Bash/Zsh.

## Tasks

### 1. Line Editor Integration (`lib/kodo/transport/line_editor.ex`)

#### Replace IO.gets with Full-Featured Line Editor
Research and integrate one of:
- **Option A**: `ratatouille_line` - Pure Elixir line editor
- **Option B**: `Liner` - Erlang-based line editor
- **Option C**: Custom implementation using ANSI escape codes

#### Line Editor Features
```elixir
defmodule Kodo.Transport.LineEditor do
  # Core line editing functionality
  def read_line(prompt, history, completion_fn)
  
  # Cursor movement
  def move_cursor(:left | :right | :home | :end, state)
  
  # Text editing
  def insert_char(char, state)
  def delete_char(:backspace | :delete, state)
  def delete_word(:backward | :forward, state)
  
  # History navigation
  def history_prev(state)
  def history_next(state)
  def history_search(pattern, state)
  
  # Line manipulation
  def clear_line(state)
  def transpose_chars(state)
  def kill_line(:to_end | :to_beginning, state)
end
```

#### Key Bindings (Emacs-style)
- `Ctrl+A` → Move to beginning of line
- `Ctrl+E` → Move to end of line  
- `Ctrl+B` → Move backward one character
- `Ctrl+F` → Move forward one character
- `Alt+B` → Move backward one word
- `Alt+F` → Move forward one word
- `Ctrl+D` → Delete character under cursor
- `Ctrl+H` → Backspace
- `Ctrl+K` → Kill to end of line
- `Ctrl+U` → Kill to beginning of line
- `Ctrl+W` → Kill previous word
- `Ctrl+Y` → Yank (paste) killed text
- `Ctrl+T` → Transpose characters
- `Ctrl+L` → Clear screen
- `Ctrl+C` → Interrupt current command
- `Ctrl+Z` → Suspend current job

### 2. Command History (`lib/kodo/core/history_manager.ex`)

#### History Storage and Management
```elixir
defmodule Kodo.Core.HistoryManager do
  use GenServer
  
  # History operations
  def start_link(session_id)
  def add_command(session_id, command)
  def get_history(session_id, limit \\ 100)
  def search_history(session_id, pattern)
  def clear_history(session_id)
  
  # History navigation
  def get_previous(session_id, current_index)
  def get_next(session_id, current_index)
  def get_at_index(session_id, index)
  
  # Persistence
  def load_from_file(session_id, file_path)
  def save_to_file(session_id, file_path)
end
```

#### History Entry Structure
```elixir
defmodule Kodo.Core.HistoryEntry do
  defstruct [
    :id,              # Unique entry ID
    :command,         # Command string
    :timestamp,       # When command was executed
    :exit_status,     # Command exit status
    :working_dir,     # Directory when command was run
    :session_id       # Session that ran command
  ]
end
```

#### History Persistence
- Save to `~/.kodo_history` file
- Configurable history size (default: 1000 entries)
- Deduplication of consecutive identical commands
- Timestamp and metadata storage
- Cross-session history sharing

#### History Commands
```elixir
defcommand "history" do
  @description "Show command history"
  @usage "history [-c] [-n] [count]"
  @meta [:builtin, :pure]
  
  def execute(args, context) do
    # Show/clear/search command history
  end
end

defcommand "!!" do
  @description "Repeat last command"
  @usage "!!"
  @meta [:builtin]
  
  def execute(_args, context) do
    # Execute previous command
  end
end
```

### 3. Tab Completion (`lib/kodo/core/completion_engine.ex`)

#### Completion Engine
```elixir
defmodule Kodo.Core.CompletionEngine do
  # Main completion dispatcher
  def complete(line, cursor_pos, context)
  
  # Complete commands (first word)
  def complete_command(partial, context)
  
  # Complete file/directory names
  def complete_filename(partial, context)
  
  # Complete environment variables
  def complete_variable(partial, context)
  
  # Complete command options
  def complete_options(command, partial, context)
  
  # Complete based on command-specific logic
  def complete_for_command(command, args, partial, context)
end
```

#### Completion Sources
1. **Built-in Commands**: From `CommandRegistry`
2. **External Commands**: From `$PATH` directories
3. **File Names**: From VFS current directory
4. **Environment Variables**: From session environment
5. **Aliases**: From session alias manager
6. **History**: Recent commands and arguments

#### Smart Completion Features
```elixir
defmodule Kodo.Core.SmartCompletion do
  # Context-aware completion
  def complete_contextual(line, cursor_pos, context)
  
  # Complete git commands and options
  def complete_git(args, partial, context)
  
  # Complete make targets
  def complete_make(args, partial, context)
  
  # Complete process IDs for kill command
  def complete_pid(args, partial, context)
  
  # Complete based on file types
  def complete_by_extension(partial, extensions, context)
end
```

#### Completion UI
- Multiple match display in columns
- Common prefix auto-completion
- Cycling through matches with Tab
- Visual indication of completion type
- Fuzzy matching support (optional)

### 4. Customizable Prompt (`lib/kodo/core/prompt_manager.ex`)

#### Prompt System
```elixir
defmodule Kodo.Core.PromptManager do
  # Generate prompt string from template
  def generate_prompt(template, context)
  
  # Built-in prompt variables
  def expand_prompt_vars(template, context)
  
  # Color and formatting support
  def apply_colors(text, color_scheme)
  
  # Dynamic prompt elements
  def get_git_status(working_dir)
  def get_load_average()
  def get_battery_status()
end
```

#### Prompt Variables
- `%u` → Username
- `%h` → Hostname
- `%w` → Current working directory
- `%W` → Basename of current directory
- `%d` → Current date
- `%t` → Current time
- `%j` → Number of active jobs
- `%?` → Exit status of last command
- `%$` → `#` if root, `$` otherwise
- `%git` → Git branch and status (if in git repo)

#### Prompt Configuration
```elixir
defmodule Kodo.Core.PromptConfig do
  defstruct [
    :template,        # Prompt template string
    :colors,          # Color scheme
    :right_prompt,    # Right-side prompt (optional)
    :continuation,    # Multi-line prompt continuation
    :git_enabled,     # Show git information
    :show_time,       # Show timestamp
    :truncate_path    # Max path length
  ]
end
```

#### Default Prompts
```bash
# Simple prompt
"kodo:%w$ "

# Fancy prompt with colors and git
"%{green}%u@%h%{reset}:%{blue}%w%{yellow}%git%{reset}$ "

# Minimalist
"%W$ "

# Power user
"[%t] %u@%h:%w %j %? $ "
```

### 5. ANSI Terminal Support (`lib/kodo/core/terminal.ex`)

#### Terminal Capabilities
```elixir
defmodule Kodo.Core.Terminal do
  # Terminal detection and capabilities
  def detect_capabilities()
  def supports_color?()
  def get_terminal_size()
  def supports_unicode?()
  
  # ANSI escape sequences
  def clear_screen()
  def move_cursor(row, col)
  def hide_cursor()
  def show_cursor()
  def save_cursor()
  def restore_cursor()
  
  # Colors and formatting
  def colorize(text, color, background \\ nil)
  def bold(text)
  def underline(text)
  def reset()
end
```

#### Color Schemes
```elixir
defmodule Kodo.Core.ColorScheme do
  # Predefined color schemes
  def default_scheme()
  def dark_scheme()
  def light_scheme()
  def minimal_scheme()
  
  # Color configuration
  def set_color(element, color)
  def get_color(element)
end
```

### 6. Enhanced Transport Layer (`lib/kodo/transport/enhanced_iex.ex`)

#### Improved IEx Transport
```elixir
defmodule Kodo.Transport.EnhancedIEx do
  @behaviour Kodo.Ports.Transport
  
  # Enhanced REPL with line editing
  def start_repl(session_id, opts \\ [])
  
  # Process input with line editor
  def read_command(prompt, history, completion_fn)
  
  # Handle special key sequences
  def handle_key_sequence(sequence, state)
  
  # Update prompt dynamically
  def update_prompt(new_prompt)
end
```

### 7. Configuration System (`lib/kodo/core/config_manager.ex`)

#### Configuration Management
```elixir
defmodule Kodo.Core.ConfigManager do
  # Load configuration from file
  def load_config(config_path \\ "~/.kodorc")
  
  # Save current configuration
  def save_config(config, config_path)
  
  # Get/set configuration values
  def get_config(key, default \\ nil)
  def set_config(key, value)
  
  # Configuration validation
  def validate_config(config)
end
```

#### Configuration File Format (`.kodorc`)
```elixir
# Kodo shell configuration

# Prompt settings
set_prompt_template "%{green}%u@%h%{reset}:%{blue}%w%{yellow}%git%{reset}$ "
set_right_prompt "%t"

# History settings
set_history_size 2000
set_history_file "~/.kodo_history"

# Completion settings
set_completion_enabled true
set_fuzzy_completion false

# Aliases
alias ll "ls -la"
alias grep "grep --color=auto"
alias ..  "cd .."

# Environment variables
export EDITOR "nvim"
export PAGER "less"

# Key bindings
bind "\\C-r" history_search
bind "\\C-t" transpose_chars
```

### 8. Testing (`test/kodo/core/`)

#### Line Editor Tests (`line_editor_test.exs`)
```elixir
test "cursor movement" do
  state = LineEditor.init("hello world")
  state = LineEditor.move_cursor(:home, state)
  assert state.cursor_pos == 0
end

test "text editing" do
  state = LineEditor.init("hello")
  state = LineEditor.insert_char(?!, state)
  assert LineEditor.get_line(state) == "hello!"
end
```

#### History Tests (`history_manager_test.exs`)
```elixir
test "add and retrieve commands" do
  HistoryManager.add_command(session_id, "ls -la")
  history = HistoryManager.get_history(session_id, 10)
  assert "ls -la" in Enum.map(history, & &1.command)
end

test "history search" do
  results = HistoryManager.search_history(session_id, "git")
  assert Enum.all?(results, &String.contains?(&1.command, "git"))
end
```

#### Completion Tests (`completion_engine_test.exs`)
```elixir
test "command completion" do
  completions = CompletionEngine.complete_command("l", context)
  assert "ls" in completions
end

test "filename completion" do
  completions = CompletionEngine.complete_filename("test", context)
  assert Enum.any?(completions, &String.starts_with?(&1, "test"))
end
```

#### Prompt Tests (`prompt_manager_test.exs`)
```elixir
test "prompt variable expansion" do
  context = %{user: "alice", hostname: "laptop", working_dir: "/home/alice"}
  prompt = PromptManager.generate_prompt("%u@%h:%w$ ", context)
  assert prompt == "alice@laptop:/home/alice$ "
end
```

### 9. Performance Optimization

#### Efficient Line Editing
- Minimize terminal I/O operations
- Batch cursor movements and updates
- Optimize redraw operations
- Cache terminal capabilities

#### Completion Performance
- Lazy loading of completion data
- Caching of command lists and file listings
- Asynchronous completion for slow operations
- Limit completion results to reasonable number

### 10. Accessibility Features

#### Screen Reader Support
- Alternative text output mode
- Disable color output for screen readers
- Verbose completion descriptions
- Clear status announcements

#### Keyboard Navigation
- Full keyboard navigation support
- Alternative key bindings for accessibility
- Configurable key binding system
- Support for different terminal types

## Success Criteria
- [ ] Line editing with full Emacs-style key bindings
- [ ] Persistent command history with search
- [ ] Intelligent tab completion for commands and files
- [ ] Customizable, dynamic prompts with color support
- [ ] Configuration file support
- [ ] Performance suitable for interactive use
- [ ] Cross-platform terminal compatibility
- [ ] All tests pass with >90% coverage

## Example Usage
```elixir
# Enhanced prompt with git info
alice@laptop:~/project main* $ ls -la

# Tab completion
alice@laptop:~/project main* $ git <TAB>
add    branch   checkout   commit   diff   log   pull   push   status

# History search (Ctrl+R)
(reverse-i-search)`git ': git commit -m "Add new feature"

# Line editing (Ctrl+A, type "echo ", Ctrl+E)
alice@laptop:~/project main* $ echo git commit -m "Add new feature"
```

## Dependencies
- Line editor library (to be chosen)
- ANSI terminal support library
- Existing `Kodo.Core` modules

## Estimated Time
2-3 weeks for implementation and testing
