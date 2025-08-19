# Jido Action Usage Rules

## Package Overview
Jido Action is a composable action framework with AI integration for building autonomous agent systems and complex workflows.

## Core Components

### Actions
Self-contained modules with validated input/output contracts:

```elixir
defmodule MyApp.Actions.Example do
  use Jido.Action,
    name: "example_action",
    description: "What this action does",
    schema: [
      input: [type: :string, required: true],
      options: [type: :map, default: %{}]
    ]

  def run(params, context) do
    {:ok, %{result: "processed"}}
  end
end
```

### Execution Engine
Execute actions with retry, timeout, and error handling:

```elixir
# Direct execution
{:ok, result} = MyAction.run(%{input: "data"}, %{})

# Production execution with retry/timeout
{:ok, result} = Jido.Exec.run(
  MyAction,
  %{input: "data"}, 
  %{},
  timeout: 5000,
  max_retries: 2
)

# Chain actions sequentially
{:ok, final} = Jido.Exec.Chain.chain([
  MyAction1,
  MyAction2
], %{input: "data"}, %{})
```

### Plans & Workflows
Execute DAG-based workflows with dependencies:

```elixir
plan = Jido.Plan.new()
|> Jido.Plan.add("step1", Action1, %{}, [])
|> Jido.Plan.add("step2", Action2, %{}, ["step1"])
|> Jido.Plan.add("step3", Action3, %{}, ["step1", "step2"])

{:ok, results} = Jido.Tools.ActionPlan.run(%{
  plan: plan,
  initial_data: %{input: "data"}
}, %{})
```

## Built-in Tools (25+)

### File Operations
```elixir
# Read file
{:ok, content} = Jido.Tools.Files.ReadFile.run(%{path: "/tmp/file.txt"}, %{})

# Write file
{:ok, _} = Jido.Tools.Files.WriteFile.run(%{
  path: "/tmp/output.txt",
  content: "data",
  create_dirs: true
}, %{})
```

### HTTP Requests
```elixir
# Simple HTTP
{:ok, response} = Jido.Tools.Req.run(%{
  method: :get,
  url: "https://api.example.com/data"
}, %{})

# Custom HTTP action
GetUser = Jido.Tools.ReqTool.new(
  url: "https://api.example.com/users/:id",
  method: :get
)
{:ok, user} = GetUser.run(%{id: "123"}, %{})
```

### GitHub Tools
```elixir
# List issues
{:ok, issues} = Jido.Tools.Github.Issues.List.run(%{
  owner: "octocat",
  repo: "Hello-World",
  state: "open"
}, %{github_token: token})

# Create issue
{:ok, issue} = Jido.Tools.Github.Issues.Create.run(%{
  owner: "octocat",
  repo: "Hello-World",
  title: "Bug Report",
  body: "Description..."
}, %{github_token: token})
```

### Arithmetic
```elixir
{:ok, result} = Jido.Tools.Arithmetic.Add.run(%{value: 5, amount: 3}, %{})
# => {:ok, %{result: 8}}
```

### Weather
```elixir
{:ok, weather} = Jido.Tools.Weather.run(%{
  location: "San Francisco, CA",
  units: "metric"
}, %{})
```

## AI Integration
Actions automatically convert to AI-compatible tool definitions:

```elixir
# Get OpenAI function definition
tool_def = MyAction.to_tool()

# Execute from AI tool call
{:ok, result} = Jido.Action.Tool.execute_action(
  MyAction,
  %{"input" => "from AI"},
  %{}
)
```

## Schema Validation
Use NimbleOptions for comprehensive parameter validation:

```elixir
schema: [
  name: [type: :string, required: true],
  age: [type: :integer, min: 0, max: 150],
  tags: [type: {:list, :string}, default: []],
  status: [type: :atom, in: [:pending, :active], default: :pending]
]
```

## Error Handling
Use structured error types:

```elixir
def run(params, _context) do
  case validate_input(params.input) do
    :ok -> {:ok, %{result: "success"}}
    :error -> {:error, Jido.Action.Error.execution_error("Invalid input")}
  end
end
```

## Lifecycle Hooks
Optional callbacks for custom behavior:

```elixir
def on_before_validate_params(params) do
  # Normalize parameters
  {:ok, normalized_params}
end

def on_after_run(result) do
  # Log or enrich result
  {:ok, enriched_result}
end

def on_error(failed_params, error, context, opts) do
  # Cleanup or compensation
  {:ok, %{compensated: true}}
end
```

## Testing
```elixir
defmodule MyActionTest do
  use ExUnit.Case

  test "processes input correctly" do
    {:ok, result} = MyAction.run(%{input: "test"}, %{})
    assert result.result == "processed"
  end

  test "validates required parameters" do
    {:error, error} = MyAction.run(%{}, %{})
    assert error.type == :invalid_input_error
  end
end
```

## Common Patterns

### Resource Management
```elixir
def run(params, _context) do
  {:ok, connection} = Database.connect()
  
  try do
    result = Database.query(connection, params.query)
    {:ok, result}
  after
    Database.disconnect(connection)
  end
end
```

### Context Usage
```elixir
def run(params, context) do
  user_id = context[:user_id]
  request_id = context[:request_id]
  
  result = process_for_user(params, user_id)
  {:ok, Map.put(result, :request_id, request_id)}
end
```

### Conditional Tool Usage
```elixir
def run(params, context) do
  case params.operation do
    :read -> Jido.Tools.Files.ReadFile.run(%{path: params.path}, context)
    :write -> Jido.Tools.Files.WriteFile.run(%{path: params.path, content: params.content}, context)
  end
end
```
