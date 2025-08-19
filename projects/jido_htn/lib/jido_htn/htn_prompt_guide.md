# HTN Domain Generation Guide for Elixir

## Table of Contents
- [HTN Domain Generation Guide for Elixir](#htn-domain-generation-guide-for-elixir)
  - [Table of Contents](#table-of-contents)
  - [Core Concepts](#core-concepts)
    - [State Management](#state-management)
    - [Domain Definition](#domain-definition)
  - [Implementation Requirements](#implementation-requirements)
    - [1. State Structure](#1-state-structure)
    - [2. Predicates](#2-predicates)
    - [3. Transformers](#3-transformers)
    - [4. Domain Building](#4-domain-building)
    - [5. Task Organization](#5-task-organization)
    - [6. Method Definition](#6-method-definition)
    - [7. Available Actions](#7-available-actions)
      - [Sleep](#sleep)
      - [Log](#log)
      - [RandomDelay](#randomdelay)
      - [Todo](#todo)
  - [Best Practices](#best-practices)

## Core Concepts

An HTN (Hierarchical Task Network) module consists of:

### State Management
- Struct definition with enforced keys
- Schema validation
- State transformations

### Domain Definition
- Compound tasks (high-level goals)
- Primitive tasks (concrete actions)
- Methods (ways to decompose tasks)
- Predicates (state conditions)
- Transformers (state mutations)

## Implementation Requirements

### 1. State Structure

Define your agent's state using a struct with enforced keys:

```elixir
defmodule MyAgent do
  use Jido.Bot,
    enforce_keys: [:id, :state_var],
    fields: [:id, :state_var],
    schema: [
      id: [type: :string, required: true],
      state_var: [type: :integer, required: true]
    ],
    default_values: [
      state_var: 0
    ]
end
```

### 2. Predicates

Predicates must follow these rules:
- Always end with question mark (?)
- Always have arity of 1
- Return boolean only
- Use clear, descriptive names

```elixir
# Good predicate examples
def can_work?(bot), do: bot.battery_level > 30
def at_location?(bot, location), do: bot.location == location
def task_complete?(bot), do: bot.work_completed >= bot.work_target

# Composition example
def ready_for_work?(bot), do: 
  at_work?(bot) and 
  has_reported?(bot) and 
  can_work?(bot)
```

### 3. Transformers

Transformers follow strict patterns:
- Always have arity of 1 (receive only state)
- Pure functions that return new state
- Can be composed using helper functions
- Must handle edge cases and bounds

```elixir
# Base transformer with logic
def move_to(bot, location) do
  %{bot | 
    location: location, 
    battery_level: max(bot.battery_level - 10, 0)
  }
end

# Public transformers with arity 1
def move_to_work(bot), do: move_to(bot, :work)
def move_to_home(bot), do: move_to(bot, :home)

# Compound transformer example
def perform_work(bot, energy_cost) do
  %{bot |
    battery_level: max(bot.battery_level - energy_cost, 0),
    work_completed: bot.work_completed + 1
  }
end

def do_light_work(bot), do: perform_work(bot, 5)
def do_heavy_work(bot), do: perform_work(bot, 15)
```

### 4. Domain Building

Use the builder pattern with HTN.Domain to construct your planning domain:

```elixir
def domain do
  alias Jido.HTN.Domain, as: D
  alias MyActions, as: T

  "AgentName"
  |> D.new()
  |> D.compound("root",
    methods: [%{subtasks: ["main_cycle"]}]
  )
  |> D.compound("main_cycle",
    methods: [
      %{
        subtasks: ["do_task", "wait", "main_cycle"],
        conditions: [&can_continue?/1]
      },
      %{
        subtasks: [],
        conditions: [&should_terminate?/1]
      }
    ]
  )
  |> D.primitive(
    "do_task",
    T.DoTask,
    preconditions: [&can_do_task?/1],
    effects: [&update_task_state/1]
  )
  |> D.allow("do_task", T.DoTask)
  |> D.build!()
end
```

### 5. Task Organization

Tasks should be organized hierarchically:
- Root task as entry point
- Compound tasks for high-level goals
- Primitive tasks for concrete actions
- Each task should have clear preconditions and effects

### 6. Method Definition

Methods should:
- Have clear conditions for when they apply
- Define ordered subtasks
- Include appropriate preconditions and effects
- Handle termination cases

### 7. Available Actions

The system provides these basic Actions for common workflows:

#### Sleep
- Pauses execution for specified duration
- Schema: `duration_ms: [type: :non_neg_integer, default: 1000]`

#### Log
- Logs messages at different levels
- Schema:
```elixir
level: [type: {:in, [:debug, :info, :warn, :error]}, default: :info]
message: [type: :string, required: true]
```

#### RandomDelay
- Introduces random delay within range
- Schema:
```elixir
min_ms: [type: :non_neg_integer, required: true]
max_ms: [type: :non_neg_integer, required: true]
```

#### Todo
- Placeholder for unimplemented Actions
- Schema: `todo: [type: :string, required: true]`

Example using Todo Action:
```elixir
|> D.primitive(
  "complex_calculation",
  {Basic.Todo, todo: "Implement calculation logic for matrix workflows"},
  preconditions: [&has_input_data?/1],
  effects: [&mark_calculation_complete/1]
)
```

Example domain using various Actions:
```elixir
def domain do
  alias Jido.HTN.Domain, as: D
  alias Jido.Actions.Basic, as: B

  "WorkerBot"
  |> D.new()
  |> D.compound("root",
    methods: [%{subtasks: ["work_cycle"]}]
  )
  |> D.compound("work_cycle",
    methods: [
      %{
        subtasks: ["start_work", "perform_work", "end_work"],
        conditions: [&can_work?/1]
      }
    ]
  )
  |> D.primitive(
    "start_work",
    {B.Log, message: "Starting work cycle"},
    preconditions: [&ready_for_work?/1]
  )
  |> D.primitive(
    "perform_work",
    {B.Todo, todo: "Implement core work logic"},
    effects: [&do_work/1]
  )
  |> D.primitive(
    "end_work",
    {B.RandomDelay, min_ms: 100, max_ms: 500},
    effects: [&complete_work/1]
  )
  |> D.allow("start_work", B.Log)
  |> D.allow("perform_work", B.Todo)
  |> D.allow("end_work", B.RandomDelay)
  |> D.build!()
end
```

## Best Practices

1. Keep predicates and transformers in the same module as the agent for better cohesion

2. Use descriptive names for tasks, predicates, and transformers:
```elixir
# Good
def battery_full?(bot), do: bot.battery_level == 100
def move_to_location(bot, location), do: %{bot | location: location}

# Avoid
def check_bat(bot), do: bot.battery_level == 100
def mv(bot, loc), do: %{bot | location: loc}
```

3. Handle edge cases in transformers:
```elixir
def decrease_battery(bot, amount) do
  new_level = max(bot.battery_level - amount, 0)
  %{bot | battery_level: new_level}
end
```

4. Use proper type specs and documentation:
```elixir
@type t :: %__MODULE__{
  id: String.t(),
  battery_level: integer(),
  location: :home | :work
}

@doc "Checks if agent can perform work based on battery level"
@spec can_work?(t()) :: boolean()
def can_work?(%__MODULE__{} = bot), do: bot.battery_level > 30
```

5. When implementing new Actions:
- Place in appropriate context module
- Follow schema definition pattern
- Implement run/2 callback
- Add to domain with D.allow/3
- Consider composing existing Actions when possible

---

By following these guidelines, you'll create maintainable, well-structured HTN modules that are easy to test and extend.