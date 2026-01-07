# Jido.AI Skills Guide

This guide covers the Skills system for organizing AI capabilities into reusable, composable units.

## Table of Contents

1. [Overview](#overview)
2. [Skill Categories](#skill-categories)
3. [LLM Skills](#llm-skills)
4. [Planning Skills](#planning-skills)
5. [Reasoning Skills](#reasoning-skills)
6. [Streaming Skills](#streaming-skills)
7. [Tool Calling Skills](#tool-calling-skills)
8. [Creating Custom Skills](#creating-custom-skills)

---

## Overview

Skills are reusable AI capabilities organized by domain. Unlike strategies (which control agent behavior), skills provide specific functionality like LLM interaction, planning, reasoning, and tool execution.

### Design Principles

- **Composable**: Skills can be combined in agents
- **Domain-organized**: Related skills grouped together
- **Action-based**: Skills use Jido.Action for operations
- **Independent**: Each skill is self-contained

### Skill Structure

```elixir
defmodule Jido.AI.MyDomain.MySkill do
  use Jido.Skill

  @impl true
  def name, do: "my_skill"

  @impl true
  def state_key, do: :my_skill_state

  @impl true
  def schema, do: [...]

  @impl true
  def list_actions, do: [...]

  @impl true
  def mount(config, agent) do
    # Initialize skill state
    {:ok, initial_state}
  end
end
```

---

## Skill Categories

| Category | Description | Module |
|----------|-------------|--------|
| **LLM** | Text generation, completion, embeddings | `Jido.AI.Skills.LLM` |
| **Planning** | Task decomposition, planning, prioritization | `Jido.AI.Skills.Planning` |
| **Reasoning** | Analysis, inference, explanation | `Jido.AI.Skills.Reasoning` |
| **Streaming** | Stream processing and management | `Jido.AI.Skills.Streaming` |
| **Tool Calling** | Tool discovery, listing, execution | `Jido.AI.Skills.ToolCalling` |

---

## LLM Skills

**Module**: `Jido.AI.Skills.LLM`

Provides core LLM interaction capabilities.

### Actions

| Action | Description | File |
|--------|-------------|------|
| `Chat` | Conversational AI interactions | `actions/chat.ex` |
| `Complete` | Text completion | `actions/complete.ex` |
| `Embed` | Embedding generation | `actions/embed.ex` |

### Usage

```elixir
defmodule MyAgent do
  use Jido.Agent,
    name: "my_agent",
    skills: [
      {Jido.AI.Skills.LLM,
        model: "anthropic:claude-sonnet-4-20250514",
        api_key: System.get_env("ANTHROPIC_API_KEY")
      }
    ]
end

# Or mount skill dynamically
{:ok, agent} = LLM.mount(agent, model: "gpt-4")
```

### Chat Action

```elixir
# Send chat message
{:ok, response} = Chat.run(%{
  "messages" => [
    %{role: "user", content: "Hello!"}
  ]
}, context)

# With system prompt
{:ok, response} = Chat.run(%{
  "messages" => messages,
  "system_prompt" => "You are a helpful assistant..."
}, context)
```

---

## Planning Skills

**Module**: `Jido.AI.Skills.Planning`

Provides task decomposition and planning capabilities.

### Actions

| Action | Description | File |
|--------|-------------|------|
| `Decompose` | Break tasks into subtasks | `actions/decompose.ex` |
| `Plan` | Create execution plans | `actions/plan.ex` |
| `Prioritize` | Rank tasks by importance | `actions/prioritize.ex` |

### Usage

```elixir
# Task decomposition
{:ok, result} = Decompose.run(%{
  "task" => "Build a web application",
  "max_depth" => 3
}, context)

# => %{
#   subtasks: [
#     "Design database schema",
#     "Create API endpoints",
#     "Build frontend UI"
#   ]
# }
```

---

## Reasoning Skills

**Module**: `Jido.AI.Skills.Reasoning`

Provides analytical and inference capabilities.

### Actions

| Action | Description | File |
|--------|-------------|------|
| `Analyze` | Data analysis | `actions/analyze.ex` |
| `Explain` | Explanation generation | `actions/explain.ex` |
| `Infer` | Logical inference | `actions/infer.ex` |

### Usage

```elixir
# Analyze data
{:ok, result} = Analyze.run(%{
  "data" => data,
  "type" => :statistical
}, context)

# Explain reasoning
{:ok, result} = Explain.run(%{
  "statement" => "The sky is blue",
  "context" => "During day"
}, context)
```

---

## Streaming Skills

**Module**: `Jido.AI.Skills.Streaming`

Provides stream management capabilities.

### Actions

| Action | Description | File |
|--------|-------------|------|
| `StartStream` | Initialize stream | `actions/start_stream.ex` |
| `ProcessTokens` | Process streaming tokens | `actions/process_tokens.ex` |
| `EndStream` | Finalize stream | `actions/end_stream.ex` |

### Usage

```elixir
# Start stream
{:ok, result} = StartStream.run(%{
  "stream_id" => "stream_123",
  "source" => :llm
}, context)

# Process tokens
{:ok, result} = ProcessTokens.run(%{
  "stream_id" => "stream_123",
  "tokens" => ["Hello", " world"]
}, context)

# End stream
{:ok, result} = EndStream.run(%{
  "stream_id" => "stream_123",
  "final_size" => 100
}, context)
```

---

## Tool Calling Skills

**Module**: `Jido.AI.Skills.ToolCalling`

Provides tool discovery and execution capabilities.

### Actions

| Action | Description | File |
|--------|-------------|------|
| `ListTools` | List available tools | `actions/list_tools.ex` |
| `CallWithTools` | Call LLM with tools | `actions/call_with_tools.ex` |
| `ExecuteTool` | Execute specific tool | `actions/execute_tool.ex` |

### Usage

```elixir
# List tools
{:ok, result} = ListTools.run(%{
  "include_sensitive" => false
}, context)

# => %{
#   tools: [
#     %{name: "calculator", description: "..."},
#     %{name: "search", description: "..."}
#   ]
# }

# Execute tool
{:ok, result} = ExecuteTool.run(%{
  "tool_name" => "calculator",
  "arguments" => %{expression: "2 + 2"}
}, context)
```

---

## Creating Custom Skills

### Step 1: Define Skill Module

```elixir
defmodule Jido.AI.Skills.MyCustom do
  @moduledoc """
  Custom skill for X functionality.
  """

  use Jido.Skill

  @impl true
  def name, do: "my_custom"

  @impl true
  def state_key, do: :my_custom_state

  @impl true
  def schema do
    [
      model: [
        type: :string,
        default: "anthropic:claude-haiku-4-5"
      ],
      api_key: [
        type: :string
      ],
      max_tokens: [
        type: :integer,
        default: 4096
      ]
    ]
  end

  @impl true
  def list_actions do
    [
      {MyCustom.Actions.Action1, %{}},
      {MyCustom.Actions.Action2, %{}}
    ]
  end

  @impl true
  def mount(config, agent) do
    # Validate configuration
    model = config[:model] || "anthropic:claude-haiku-4-5"

    # Initialize skill state
    state = %{
      model: model,
      call_count: 0
    }

    {:ok, state}
  end
end
```

### Step 2: Define Actions

```elixir
defmodule Jido.AI.Skills.MyCustom.Actions.Action1 do
  @moduledoc """
  First action for MyCustom skill.
  """

  use Jido.Action

  @impl true
  def name, do: "my_custom_action1"

  @impl true
  def description, do: "Does something useful"

  @impl true
  def schema do
    [
      input: [
        type: :string,
        required: true
      ]
    ]
  end

  @impl true
  def run(params, context) do
    input = params["input"]

    # Access skill state
    skill_state = Map.get(context, :my_custom_state, %{})

    # Do work
    result = process(input, skill_state)

    {:ok, %{result: result}}
  end

  defp process(input, state) do
    # Implementation
    "Processed: #{input}"
  end
end
```

### Step 3: Use in Agent

```elixir
defmodule MyAgent do
  use Jido.Agent,
    name: "my_agent",
    skills: [
      {Jido.AI.Skills.MyCustom,
        model: "anthropic:claude-sonnet-4-20250514",
        max_tokens: 8192
      }
    ]
end
```

---

## Skill Lifecycle

### Mounting

```elixir
# Skills are mounted when agent starts
def mount(config, agent) do
  # 1. Validate configuration
  # 2. Initialize state
  # 3. Register actions
  # 4. Return {:ok, state}
end
```

### State Management

```elixir
# Access skill state in actions
skill_state = context[:my_custom_state]

# Update skill state
{:ok, agent} = Jido.Agent.update_state(agent, fn state ->
  put_in(state, [:my_custom_state, :last_result], result)
end)
```

### Unmounting

```elixir
# Skills are unmounted when agent stops
# Use for cleanup
def unmount(agent, state) do
  # Clean up resources
  {:ok, agent}
end
```

---

## Best Practices

### 1. Organize by Domain

```elixir
# ✅ Good - Domain-specific actions
defmodule MathSkills do
  use Jido.Skill
  def list_actions do
    [
      {Math.Actions.Add, %{}},
      {Math.Actions.Subtract, %{}},
      {Math.Actions.Multiply, %{}}
    ]
  end
end

# ❌ Bad - Mixed domains
defmodule EverythingSkills do
  use Jido.Skill
  def list_actions do
    [
      {Math.Actions.Add, %{}},
      {Writing.Actions.Compose, %{}},
      {Database.Actions.Query, %{}}
    ]
  end
end
```

### 2. Use Clear Names

```elixir
# ✅ Good
def name, do: "math_calculator"

# ❌ Bad
def name, do: :helper
```

### 3. Provide Schemas

```elixir
@schema [
  input: [
    type: :string,
    required: true,
    doc: "The input to process"
  ],
  options: [
    type: :map,
    default: %{},
    doc: "Optional processing options"
  ]
]
```

### 4. Handle Errors

```elixir
def run(params, context) do
  try do
    result = do_work(params)
    {:ok, %{result: result}}
  rescue
    e ->
      {:error, "Processing failed: #{Exception.message(e)}"}
  end
end
```

---

## Related Guides

- [Architecture Overview](./01_architecture_overview.md) - System architecture
- [Tool System Guide](./06_tool_system.md) - Tool execution
- [Strategies Guide](./02_strategies.md) - Strategy integration
