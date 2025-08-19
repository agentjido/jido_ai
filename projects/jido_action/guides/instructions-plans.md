# Instructions & Plans

**Prerequisites**: [Execution Engine](execution-engine.md)

Instructions wrap actions with runtime parameters, while Plans orchestrate multiple instructions into complex DAG-based workflows with dependency management.

## Instructions

Instructions standardize how actions are executed by combining the action module, parameters, context, and runtime options.

### Instruction Structure

```elixir
%Jido.Instruction{
  id: "inst_abc123",                    # Auto-generated unique ID
  action: MyApp.Actions.ProcessData,    # Action module to execute
  params: %{data: "input"},             # Parameters for the action
  context: %{user_id: "123"},           # Execution context
  opts: [timeout: 5000]                 # Runtime options
}
```

### Creating Instructions

Multiple formats for flexibility:

```elixir
# 1. Full struct (most explicit)
%Jido.Instruction{
  action: MyApp.Actions.ProcessData,
  params: %{data: "input"},
  context: %{user_id: "123"},
  opts: [timeout: 5000]
}

# 2. Action module only (minimal)
MyApp.Actions.ProcessData

# 3. Action with parameters (common)
{MyApp.Actions.ProcessData, %{data: "input"}}

# 4. Factory function (programmatic)
{:ok, instruction} = Jido.Instruction.new(%{
  action: MyApp.Actions.ProcessData,
  params: %{data: "input"},
  context: %{user_id: "123"}
})
```

### Instruction Normalization

Convert various formats to standard instruction structs:

```elixir
# Normalize single instruction
{:ok, [instruction]} = Jido.Instruction.normalize(
  {MyApp.Actions.ProcessData, %{data: "input"}}
)

# Normalize list with shared context
{:ok, instructions} = Jido.Instruction.normalize(
  [
    MyApp.Actions.ValidateInput,
    {MyApp.Actions.ProcessData, %{format: "json"}},
    MyApp.Actions.SaveOutput
  ],
  %{request_id: "req_123"}  # Applied to all instructions
)

# Result: List of normalized Jido.Instruction structs
```

## Plans

Plans orchestrate multiple instructions into complex workflows using Directed Acyclic Graphs (DAGs) with dependency management and parallel execution.

### Basic Plan Creation

```elixir
# Create a new plan
plan = Jido.Plan.new()

# Add instructions with dependencies
plan = plan
|> Jido.Plan.add("validate", MyApp.Actions.ValidateInput, %{}, [])
|> Jido.Plan.add("process", MyApp.Actions.ProcessData, %{}, ["validate"])
|> Jido.Plan.add("save", MyApp.Actions.SaveOutput, %{}, ["process"])
|> Jido.Plan.add("notify", MyApp.Actions.SendNotification, %{}, ["save"])
```

### Advanced Plan Structure

```elixir
# Complex workflow with parallel branches
plan = Jido.Plan.new()
|> Jido.Plan.add("input", MyApp.Actions.ValidateInput, %{}, [])

# Parallel processing branches
|> Jido.Plan.add("process_a", MyApp.Actions.ProcessTypeA, %{}, ["input"])
|> Jido.Plan.add("process_b", MyApp.Actions.ProcessTypeB, %{}, ["input"])
|> Jido.Plan.add("process_c", MyApp.Actions.ProcessTypeC, %{}, ["input"])

# Convergence point
|> Jido.Plan.add("merge", MyApp.Actions.MergeResults, %{}, ["process_a", "process_b", "process_c"])
|> Jido.Plan.add("finalize", MyApp.Actions.Finalize, %{}, ["merge"])
```

### Plan Execution Phases

The plan system automatically calculates execution phases based on dependencies:

```
Phase 1: [input]                           # No dependencies
Phase 2: [process_a, process_b, process_c] # Depend on input, run in parallel
Phase 3: [merge]                           # Depends on all process_* actions
Phase 4: [finalize]                        # Depends on merge
```

### Using ActionPlan Tool

Execute plans using the built-in ActionPlan tool:

```elixir
# Create plan instruction
plan_instruction = %Jido.Instruction{
  action: Jido.Tools.ActionPlan,
  params: %{
    plan: plan,
    initial_data: %{input: "data to process"}
  },
  context: %{user_id: "123"}
}

# Execute the plan
{:ok, results} = Jido.Exec.run(
  Jido.Tools.ActionPlan,
  %{
    plan: plan,
    initial_data: %{input: "data to process"}
  },
  %{user_id: "123"}
)

# Results contain outputs from all executed instructions
# %{
#   "input" => %{validated: true, data: "..."},
#   "process_a" => %{result: "..."},
#   "process_b" => %{result: "..."},
#   # ... etc
# }
```

## Data Flow

### Context Propagation

Context flows through the entire execution chain:

```elixir
# Initial context
context = %{
  request_id: "req_123",
  user_id: "user_456", 
  tenant_id: "tenant_789"
}

# Available in all instructions
plan = Jido.Plan.new()
|> Jido.Plan.add("step1", MyApp.Actions.Step1, %{}, [])
|> Jido.Plan.add("step2", MyApp.Actions.Step2, %{}, ["step1"])

# Execute with context
{:ok, results} = Jido.Exec.run(
  Jido.Tools.ActionPlan,
  %{plan: plan, initial_data: %{}},
  context  # Flows to all actions
)
```

### Parameter Flow Between Actions

```elixir
defmodule MyApp.Actions.ProduceData do
  use Jido.Action,
    name: "produce_data",
    schema: [type: [type: :string, required: true]]

  def run(%{type: type}, _context) do
    data = generate_data(type)
    {:ok, %{generated_data: data, metadata: %{type: type}}}
  end
end

defmodule MyApp.Actions.ConsumeData do
  use Jido.Action,
    name: "consume_data", 
    schema: [generated_data: [type: :string, required: true]]

  def run(%{generated_data: data}, _context) do
    processed = process_data(data)
    {:ok, %{processed: processed}}
  end
end

# Plan automatically flows data between actions
plan = Jido.Plan.new()
|> Jido.Plan.add("produce", MyApp.Actions.ProduceData, %{type: "json"}, [])
|> Jido.Plan.add("consume", MyApp.Actions.ConsumeData, %{}, ["produce"])
```

## Error Handling in Plans

### Plan-Level Error Handling

```elixir
case Jido.Exec.run(
  Jido.Tools.ActionPlan,
  %{plan: plan, initial_data: initial_data},
  context
) do
  {:ok, results} ->
    handle_success(results)
  
  {:error, {failed_instruction_id, error, partial_results}} ->
    # Know which instruction failed and what completed
    Logger.error("Plan failed at #{failed_instruction_id}: #{error.message}")
    handle_partial_completion(partial_results)
end
```

### Compensation in Plans

```elixir
defmodule MyApp.Actions.CriticalOperation do
  use Jido.Action,
    name: "critical_operation",
    compensation: [enabled: true]

  def run(params, context) do
    # Critical operation that might need compensation
    case perform_critical_work(params) do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, reason}
    end
  end

  def on_error(failed_params, error, context, opts) do
    # Compensation logic
    cleanup_critical_resources(failed_params)
    {:ok, %{compensated: true}}
  end
end
```

## Common Patterns

### Fan-Out-Fan-In

Process multiple items in parallel, then merge results:

```elixir
defmodule MyApp.Workflows.FanOutFanIn do
  def create_plan(items) do
    plan = Jido.Plan.new()
    |> Jido.Plan.add("prepare", MyApp.Actions.PrepareItems, %{items: items}, [])
    
    # Add parallel processing for each item
    plan = Enum.reduce(items, plan, fn item, acc_plan ->
      Jido.Plan.add(acc_plan, "process_#{item.id}", 
        MyApp.Actions.ProcessItem, 
        %{item: item}, 
        ["prepare"]
      )
    end)
    
    # Add convergence point
    process_deps = Enum.map(items, &"process_#{&1.id}")
    plan |> Jido.Plan.add("merge", MyApp.Actions.MergeResults, %{}, process_deps)
  end
end
```

### Conditional Execution

```elixir
defmodule MyApp.Actions.ConditionalStep do
  use Jido.Action,
    name: "conditional_step",
    schema: [condition: [type: :boolean, required: true]]

  def run(%{condition: false}, _context) do
    # Skip execution
    {:ok, %{skipped: true}}
  end
  
  def run(%{condition: true}, context) do
    # Perform the work
    result = perform_work(context)
    {:ok, result}
  end
end
```

### Pipeline Pattern

Transform data through a series of steps:

```elixir
# ETL Pipeline
pipeline_plan = Jido.Plan.new()
|> Jido.Plan.add("extract", MyApp.Actions.ExtractData, %{source: "db"}, [])
|> Jido.Plan.add("validate", MyApp.Actions.ValidateData, %{}, ["extract"])
|> Jido.Plan.add("transform", MyApp.Actions.TransformData, %{}, ["validate"])
|> Jido.Plan.add("enrich", MyApp.Actions.EnrichData, %{}, ["transform"])
|> Jido.Plan.add("load", MyApp.Actions.LoadData, %{target: "warehouse"}, ["enrich"])
```

### Error Recovery Pipeline

```elixir
# Pipeline with fallback steps
recovery_plan = Jido.Plan.new()
|> Jido.Plan.add("primary", MyApp.Actions.PrimaryOperation, %{}, [])
|> Jido.Plan.add("fallback", MyApp.Actions.FallbackOperation, %{}, ["primary"])
|> Jido.Plan.add("notify", MyApp.Actions.NotifyFailure, %{}, ["fallback"])

# Fallback action only runs if primary fails
defmodule MyApp.Actions.FallbackOperation do
  def run(params, context) do
    # Check if primary succeeded
    case Map.get(context, :results, %{})["primary"] do
      {:ok, _} -> 
        {:ok, %{skipped: true, reason: "primary succeeded"}}
      {:error, _} ->
        # Primary failed, run fallback
        perform_fallback_operation(params)
    end
  end
end
```

## Best Practices

### Plan Design
- **Clear Dependencies**: Only specify necessary dependencies
- **Parallel Opportunities**: Identify steps that can run concurrently
- **Error Boundaries**: Group related operations for better error handling
- **Data Locality**: Minimize data transfer between distant steps

### Instruction Organization
- **Descriptive IDs**: Use meaningful instruction identifiers
- **Parameter Isolation**: Keep instruction parameters focused and minimal
- **Context Usage**: Use context for cross-cutting concerns, not business data

### Performance
- **Phase Optimization**: Design for optimal phase execution
- **Resource Management**: Consider resource usage in parallel phases
- **Memory Usage**: Be mindful of data accumulation in long plans

## Next Steps

**→ [Error Handling Guide](error-handling.md)** - Advanced error patterns  
**→ [Built-in Tools](tools-reference.md)** - Explore available actions  
**→ [AI Integration](ai-integration.md)** - Using plans with AI systems

---
← [Execution Engine](execution-engine.md) | **Next: [Error Handling Guide](error-handling.md)** →
