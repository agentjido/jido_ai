# Jido.AI State Machines Guide

This guide covers the pure functional state machines used in Jido.AI strategies, implemented with Fsmx.

## Table of Contents

1. [Overview](#overview)
2. [Fsmx Basics](#fsmx-basics)
3. [State Machine Pattern](#state-machine-pattern)
4. [ReAct Machine](#react-machine)
5. [Chain-of-Thought Machine](#chain-of-thought-machine)
6. [Tree-of-Thoughts Machine](#tree-of-thoughts-machine)
7. [TRM Machine](#trm-machine)
8. [Creating Custom Machines](#creating-custom-machines)

---

## Overview

All Jido.AI strategies use **pure functional state machines** for core logic:

- **Pure**: No side effects in state transitions
- **Predictable**: Same input → same output
- **Testable**: Easy to unit test
- **Observable**: All state changes explicit

The state machine returns **directives** that describe external effects:

```elixir
{machine, directives} = Machine.update(machine, message, env)
```

---

## Fsmx Basics

Jido.AI uses [Fsmx](https://hex.pm/packages/fsmx) for state machine management.

### Defining Transitions

```elixir
use Fsmx.Struct,
  state_field: :status,
  transitions: %{
    "idle" => ["processing", "error"],
    "processing" => ["completed", "error"],
    "completed" => [],
    "error" => []
  }
```

### Transitioning States

```elixir
case Fsmx.transition(machine, "processing", state_field: :status) do
  {:ok, updated_machine} ->
    # Transition succeeded
  {:error, _reason} ->
    # Invalid transition
end
```

### With Transition Helper

```elixir
defp with_transition(machine, new_status, fun) do
  case Fsmx.transition(machine, new_status, state_field: :status) do
    {:ok, machine} -> fun.(machine)
    {:error, _} -> {machine, []}
  end
end

# Usage
with_transition(machine, "processing", fn machine ->
  {machine, [{:some_directive, ...}]}
end)
```

---

## State Machine Pattern

All state machines follow this pattern:

```elixir
defmodule Jido.AI.MyStrategy.Machine do
  @moduledoc """
  Pure state machine for MyStrategy.
  """

  use Fsmx.Struct,
    state_field: :status,
    transitions: %{
      "idle" => ["processing"],
      "processing" => ["completed", "error"],
      "completed" => [],
      "error" => []
    }

  @type status :: :idle | :processing | :completed | :error

  @type t :: %__MODULE__{
          status: String.t(),
          result: term(),
          started_at: integer() | nil
        }

  defstruct status: "idle",
            result: nil,
            started_at: nil

  @type msg ::
          {:start, prompt :: String.t(), call_id :: String.t()}
          | {:llm_result, call_id :: String.t(), result :: term()}

  @type directive :: {:some_directive, id :: String.t(), context :: term()}

  @doc """
  Creates a new machine in the idle state.
  """
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc """
  Updates the machine state based on a message.
  """
  @spec update(t(), msg(), map()) :: {t(), [directive()]}
  def update(%__MODULE__{status: "idle"} = machine, {:start, prompt, call_id}, _env) do
    with_transition(machine, "processing", fn machine ->
      machine = %{machine | started_at: System.monotonic_time(:millisecond)}
      {machine, [{:some_directive, call_id, %{prompt: prompt}}]}
    end)
  end

  def update(%__MODULE__{status: "processing"} = machine, {:llm_result, _call_id, result}, _env) do
    with_transition(machine, "completed", fn machine ->
      machine = %{machine | result: result}
      {machine, []}
    end)
  end

  def update(machine, _msg, _env) do
    {machine, []}
  end

  @doc """
  Converts the machine state to a map for storage.
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = machine), do: Map.from_struct(machine)

  @doc """
  Creates a machine from a map.
  """
  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map), do: struct(__MODULE__, map)

  @doc """
  Generates a unique call ID.
  """
  @spec generate_call_id() :: String.t()
  def generate_call_id, do: "call_#{Jido.Util.generate_id()}"
end
```

---

## ReAct Machine

**Module**: `Jido.AI.ReAct.Machine`

### States

```
idle → awaiting_llm → awaiting_tool → awaiting_llm → ... → completed
                    ↓                              ↓
                  error                          error
```

### State Structure

```elixir
@type t :: %__MODULE__{
        status: String.t(),                          # Current state
        iteration: non_neg_integer(),                # Current iteration
        conversation: list(),                        # Message history
        pending_tool_calls: [pending_tool_call()],    # Tools being executed
        result: term(),                              # Final result
        current_llm_call_id: String.t() | nil,       # Active LLM call
        termination_reason: termination_reason(),     # How it ended
        streaming_text: String.t(),                  # Accumulated stream
        streaming_thinking: String.t(),              # Thinking tokens
        usage: usage(),                              # Token usage
        started_at: integer() | nil                 # Start time
      }
```

### Message Handling

```elixir
# Start reasoning
{:start, query, call_id}

# LLM responded
{:llm_result, call_id, {:ok, %{type: :tool_calls, tool_calls: [...]}}}
{:llm_result, call_id, {:ok, %{type: :final_answer, text: "..."}}}
{:llm_result, call_id, {:error, reason}}

# Streaming token
{:llm_partial, call_id, delta, :content | :thinking}

# Tool executed
{:tool_result, call_id, {:ok, result}}
{:tool_result, call_id, {:error, reason}}
```

### Directives

```elixir
{:call_llm_stream, id, conversation}
{:exec_tool, id, tool_name, arguments}
```

---

## Chain-of-Thought Machine

**Module**: `Jido.AI.ChainOfThought.Machine`

### States

```
idle → reasoning → completed
                   ↓
                 error
```

### State Structure

```elixir
@type t :: %__MODULE__{
        status: String.t(),
        prompt: String.t() | nil,
        reasoning: String.t(),
        steps: [step()],              # Extracted steps
        conclusion: String.t(),       # Final conclusion
        result: term(),
        current_llm_call_id: String.t() | nil,
        termination_reason: termination_reason(),
        streaming_text: String.t(),
        usage: usage(),
        started_at: integer() | nil
      }

@type step :: %{
        number: pos_integer(),
        content: String.t()
      }
```

### Step Extraction

```elixir
# Extract steps from response
%{steps: steps, conclusion: conclusion, remaining_text: rest} =
  ChainOfThought.Machine.extract_steps(response_text)

# Supported formats:
# - "Step 1: First..."
# - "1. First..."
# - "- First..."
```

---

## Tree-of-Thoughts Machine

**Module**: `Jido.AI.TreeOfThoughts.Machine`

### State Structure

```elixir
@type t :: %__MODULE__{
        status: String.t(),
        nodes: %{String.t() => thought_node()},  # Tree nodes
        edges: [edge()],                          # Tree edges
        current_node_id: String.t() | nil,
        solution_path: [String.t()],              # Root to solution
        frontier: [String.t()],                   # Nodes to expand
        branching_factor: pos_integer(),
        max_depth: pos_integer(),
        traversal_strategy: traversal_strategy(),
        # ... other fields
      }

@type thought_node :: %{
        id: String.t(),
        content: String.t(),
        depth: non_neg_integer(),
        score: float(),
        parent_id: String.t() | nil,
        children: [String.t()]
      }
```

### Tree Operations

```elixir
# Find best leaf node
best_node = Machine.find_best_leaf(machine)

# Trace path from root to node
path = Machine.trace_path(machine, node_id)

# Get all leaf nodes
leaves = Machine.get_leaves(machine)
```

---

## TRM Machine

**Module**: `Jido.AI.TRM.Machine`

### States

```
idle → reasoning → supervising → improving → reasoning → ...
       ↓            ↓            ↓           ↓
     completed    error        error       error
```

### State Structure

```elixir
@type t :: %__MODULE__{
        status: String.t(),
        phase: :reasoning | :supervising | :improving,
        question: String.t(),
        current_answer: String.t(),
        answer_history: [String.t()],
        best_answer: String.t() | nil,
        best_score: float(),
        supervision_step: non_neg_integer(),
        max_supervision_steps: pos_integer(),
        act_threshold: float(),
        act_triggered: boolean(),
        latent_state: map(),
        usage: usage(),
        started_at: integer() | nil
      }
```

### Phase Transitions

```elixir
# Reasoning phase
{:start, question, call_id}

# Supervision phase (evaluate quality)
{:supervision_result, call_id, result}

# Improvement phase (apply feedback)
{:improvement_result, call_id, result}
```

---

## Creating Custom Machines

### Step 1: Define States and Transitions

```elixir
use Fsmx.Struct,
  state_field: :status,
  transitions: %{
    "idle" => ["in_progress"],
    "in_progress" => ["succeeded", "failed"],
    "succeeded" => [],
    "failed" => []
  }
```

### Step 2: Define Struct

```elixir
defstruct status: "idle",
          input: nil,
          result: nil,
          error: nil,
          started_at: nil,
          completed_at: nil
```

### Step 3: Implement update/3

```elixir
def update(%__MODULE__{status: "idle"} = machine, {:start, input}, _env) do
  with_transition(machine, "in_progress", fn machine ->
    machine = %{machine
      | input = input
      | started_at = System.monotonic_time(:millisecond)
    }
    directives = [{:do_work, generate_id(), %{input: input}}]
    {machine, directives}
  end)
end

def update(%__MODULE__{status: "in_progress"} = machine, {:work_complete, result}, _env) do
  with_transition(machine, "succeeded", fn machine ->
    machine = %{machine
      | result = result
      | completed_at = System.monotonic_time(:millisecond)
    }
    {machine, [{:notify_complete, result}]}
  end)
end

def update(%__MODULE__{status: "in_progress"} = machine, {:work_failed, error}, _env) do
  with_transition(machine, "failed", fn machine ->
    machine = %{machine
      | error = error
      | completed_at = System.monotonic_time(:millisecond)
    }
    {machine, [{:notify_failed, error}]}
  end)
end

def update(machine, _msg, _env) do
  {machine, []}
end
```

### Step 4: Serialization

```elixir
def to_map(%__MODULE__{} = machine), do: Map.from_struct(machine)

def from_map(map) when is_map(map) do
  struct(__MODULE__, map)
end
```

---

## Best Practices

### 1. Keep State Pure

```elixir
# ❌ Bad - side effects
def update(machine, msg, _env) do
  File.write("/tmp/state", inspect(machine))  # Side effect!
  {machine, []}
end

# ✅ Good - pure function
def update(machine, msg, _env) do
  new_machine = %{machine | result: process(msg)}
  {new_machine, [{:log_state, new_machine}]}  # Directive describes effect
end
```

### 2. Handle All Messages

```elixir
def update(machine, {:specific_msg, _}, _env), do: # handle specific
def update(machine, _msg, _env), do: {machine, []}  # fallback
```

### 3. Emit Telemetry

```elixir
@telemetry_prefix [:jido, :ai, :my_strategy]

defp emit_telemetry(event, measurements, metadata) do
  :telemetry.execute(@telemetry_prefix ++ [event], measurements, metadata)
end

# Usage
emit_telemetry(:start, %{system_time: System.system_time()}, %{call_id: call_id})
emit_telemetry(:complete, %{duration: duration_ms}, %{status: status})
```

### 4. Track Token Usage

```elixir
defp accumulate_usage(machine, result) do
  case Map.get(result, :usage) do
    nil -> machine
    new_usage when is_map(new_usage) ->
      %{machine | usage: Map.merge(machine.usage || %{}, new_usage)}
  end
end
```

---

## Related Guides

- [Architecture Overview](./01_architecture_overview.md) - System architecture
- [Strategies Guide](./02_strategies.md) - Strategy implementations
- [Directives Guide](./04_directives.md) - Directive system
