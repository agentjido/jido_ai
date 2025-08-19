# Built-in Tools Reference

**Prerequisites**: [Getting Started](getting-started.md)

Jido Action includes 25+ pre-built tools for common operations. All tools follow the same action patterns and can be used individually or composed into workflows.

## Basic Tools

### Sleep
Pause execution for a specified duration.

```elixir
# Sleep for 1 second
{:ok, result} = Jido.Tools.Basic.Sleep.run(%{duration_ms: 1000}, %{})
# => {:ok, %{slept_for: 1000, completed_at: ~U[2024-01-15 10:30:45Z]}}

# Use in workflows for delays
plan = Jido.Plan.new()
|> Jido.Plan.add("process", MyApp.Actions.ProcessData, %{}, [])
|> Jido.Plan.add("wait", Jido.Tools.Basic.Sleep, %{duration_ms: 5000}, ["process"])
|> Jido.Plan.add("notify", MyApp.Actions.SendNotification, %{}, ["wait"])
```

**Parameters:**
- `duration_ms` (integer, required): Milliseconds to sleep

## Arithmetic Tools

### Add
Add a value to a number.

```elixir
{:ok, result} = Jido.Tools.Arithmetic.Add.run(%{value: 10, amount: 5}, %{})
# => {:ok, %{result: 15}}
```

**Parameters:**
- `value` (number, required): Base value
- `amount` (number, required): Amount to add

### Subtract
Subtract a value from a number.

```elixir
{:ok, result} = Jido.Tools.Arithmetic.Subtract.run(%{value: 10, amount: 3}, %{})
# => {:ok, %{result: 7}}
```

### Multiply
Multiply a number by a factor.

```elixir
{:ok, result} = Jido.Tools.Arithmetic.Multiply.run(%{value: 6, factor: 4}, %{})
# => {:ok, %{result: 24}}
```

### Divide
Divide a number by a divisor.

```elixir
{:ok, result} = Jido.Tools.Arithmetic.Divide.run(%{value: 20, divisor: 4}, %{})
# => {:ok, %{result: 5.0}}

# Division by zero returns error
{:error, error} = Jido.Tools.Arithmetic.Divide.run(%{value: 10, divisor: 0}, %{})
# => {:error, %{message: "Division by zero"}}
```

## File Operations

### Read File
Read contents from a file.

```elixir
{:ok, result} = Jido.Tools.Files.ReadFile.run(%{path: "/tmp/data.txt"}, %{})
# => {:ok, %{content: "file contents", size: 13, path: "/tmp/data.txt"}}

# Handle missing files
{:error, error} = Jido.Tools.Files.ReadFile.run(%{path: "/nonexistent.txt"}, %{})
# => {:error, %{message: "File not found"}}
```

**Parameters:**
- `path` (string, required): File path to read
- `encoding` (string, default: "utf8"): File encoding

### Write File
Write content to a file.

```elixir
{:ok, result} = Jido.Tools.Files.WriteFile.run(%{
  path: "/tmp/output.txt",
  content: "Hello, World!",
  create_dirs: true
}, %{})
# => {:ok, %{path: "/tmp/output.txt", size: 13, created_dirs: true}}
```

**Parameters:**
- `path` (string, required): File path to write
- `content` (string, required): Content to write
- `create_dirs` (boolean, default: false): Create parent directories
- `encoding` (string, default: "utf8"): File encoding

### Delete File
Delete a file.

```elixir
{:ok, result} = Jido.Tools.Files.DeleteFile.run(%{path: "/tmp/temp.txt"}, %{})
# => {:ok, %{deleted: true, path: "/tmp/temp.txt"}}
```

### List Directory
List files in a directory.

```elixir
{:ok, result} = Jido.Tools.Files.ListDirectory.run(%{
  path: "/tmp",
  include_hidden: false
}, %{})
# => {:ok, %{files: ["file1.txt", "file2.txt"], count: 2}}
```

**Parameters:**
- `path` (string, required): Directory path
- `include_hidden` (boolean, default: false): Include hidden files

## HTTP Tools

### ReqTool (HTTP Request Builder)
Create custom HTTP request actions.

```elixir
# Create a specific API endpoint action
GetUser = Jido.Tools.ReqTool.new(
  url: "https://api.example.com/users/:id",
  method: :get,
  headers: %{"Authorization" => "Bearer #{api_token}"}
)

# Use the generated action
{:ok, response} = GetUser.run(%{id: "123"}, %{})
# => {:ok, %{status: 200, body: %{"id" => "123", "name" => "John"}}}

# POST with body
CreateUser = Jido.Tools.ReqTool.new(
  url: "https://api.example.com/users",
  method: :post,
  headers: %{"Content-Type" => "application/json"}
)

{:ok, response} = CreateUser.run(%{
  body: %{name: "Jane", email: "jane@example.com"}
}, %{})
```

**Template Variables:**
- URL templates support `:variable` syntax
- Variables are replaced from parameters

**Common Parameters:**
- `body` (any): Request body (auto-encoded to JSON)
- `headers` (map): Additional headers
- `query` (map): Query parameters
- `timeout` (integer): Request timeout in milliseconds

### Req (Simple HTTP)
Make basic HTTP requests.

```elixir
# GET request
{:ok, response} = Jido.Tools.Req.run(%{
  method: :get,
  url: "https://httpbin.org/json"
}, %{})

# POST with JSON body
{:ok, response} = Jido.Tools.Req.run(%{
  method: :post,
  url: "https://httpbin.org/post",
  body: %{name: "test", value: 123},
  headers: %{"Content-Type" => "application/json"}
}, %{})
```

## GitHub Tools

### List Issues
List GitHub repository issues.

```elixir
{:ok, issues} = Jido.Tools.Github.Issues.List.run(%{
  owner: "octocat",
  repo: "Hello-World",
  state: "open",
  per_page: 10
}, %{github_token: token})
# => {:ok, %{issues: [...], count: 5}}
```

**Parameters:**
- `owner` (string, required): Repository owner
- `repo` (string, required): Repository name
- `state` (string, default: "open"): Issue state ("open", "closed", "all")
- `labels` (list): Filter by labels
- `per_page` (integer, default: 30): Results per page

### Create Issue
Create a new GitHub issue.

```elixir
{:ok, issue} = Jido.Tools.Github.Issues.Create.run(%{
  owner: "octocat",
  repo: "Hello-World",
  title: "Bug Report",
  body: "Description of the bug...",
  labels: ["bug", "priority-high"]
}, %{github_token: token})
# => {:ok, %{number: 123, id: 456789, url: "https://..."}}
```

### Update Issue
Update an existing GitHub issue.

```elixir
{:ok, issue} = Jido.Tools.Github.Issues.Update.run(%{
  owner: "octocat",
  repo: "Hello-World",
  number: 123,
  state: "closed",
  labels: ["bug", "resolved"]
}, %{github_token: token})
```

### Find Issue
Find issues by criteria.

```elixir
{:ok, results} = Jido.Tools.Github.Issues.Find.run(%{
  owner: "octocat",
  repo: "Hello-World",
  query: "is:open label:bug",
  sort: "created",
  order: "desc"
}, %{github_token: token})
```

### Filter Issues
Filter issues with advanced criteria.

```elixir
{:ok, filtered} = Jido.Tools.Github.Issues.Filter.run(%{
  issues: existing_issues,
  state: "open",
  has_labels: ["bug"],
  created_after: "2024-01-01",
  assignee: "username"
}, %{})
```

## Weather Tools

### Get Weather
Fetch current weather data.

```elixir
{:ok, weather} = Jido.Tools.Weather.run(%{
  location: "San Francisco, CA",
  units: "metric"
}, %{})
# => {:ok, %{
#   temperature: 18.5,
#   humidity: 65,
#   description: "partly cloudy",
#   location: "San Francisco, CA"
# }}
```

**Parameters:**
- `location` (string, required): Location name or coordinates
- `units` (string, default: "metric"): Temperature units ("metric", "imperial")

## Workflow Tools

### ActionPlan
Execute complex DAG-based workflows.

```elixir
# Create a plan
plan = Jido.Plan.new()
|> Jido.Plan.add("validate", MyApp.Actions.ValidateInput, %{}, [])
|> Jido.Plan.add("process_a", MyApp.Actions.ProcessA, %{}, ["validate"])
|> Jido.Plan.add("process_b", MyApp.Actions.ProcessB, %{}, ["validate"])
|> Jido.Plan.add("merge", MyApp.Actions.MergeResults, %{}, ["process_a", "process_b"])

# Execute the plan
{:ok, results} = Jido.Tools.ActionPlan.run(%{
  plan: plan,
  initial_data: %{input: "data to process"}
}, %{user_id: "123"})
# => {:ok, %{
#   "validate" => %{...},
#   "process_a" => %{...},
#   "process_b" => %{...},
#   "merge" => %{...}
# }}
```

**Parameters:**
- `plan` (Jido.Plan, required): Plan to execute
- `initial_data` (map, default: %{}): Initial data for the plan

### Workflow
Execute simple sequential workflows.

```elixir
{:ok, result} = Jido.Tools.Workflow.run(%{
  steps: [
    {MyApp.Actions.Step1, %{param: "value1"}},
    {MyApp.Actions.Step2, %{param: "value2"}},
    MyApp.Actions.Step3
  ],
  initial_data: %{input: "start"}
}, %{})
```

## Advanced Tools

### Simplebot
A demonstration AI-like action for testing.

```elixir
{:ok, response} = Jido.Tools.Simplebot.run(%{
  message: "Hello, how are you?",
  context: %{user_name: "Alice"}
}, %{})
# => {:ok, %{response: "Hello Alice! I'm doing well, thank you for asking."}}
```

**Parameters:**
- `message` (string, required): Input message
- `context` (map, default: %{}): Additional context

## Tool Composition

### Chaining Tools

```elixir
# Chain multiple tools together
{:ok, final_result} = Jido.Exec.Chain.chain([
  # Read data from file
  {Jido.Tools.Files.ReadFile, %{path: "/tmp/input.txt"}},
  
  # Process with custom action
  {MyApp.Actions.ProcessText, %{}},
  
  # Write result to new file
  {Jido.Tools.Files.WriteFile, %{
    path: "/tmp/output.txt", 
    create_dirs: true
  }}
], %{}, %{user_id: "123"})
```

### Parallel Tool Execution

```elixir
# Execute tools in parallel using plans
parallel_plan = Jido.Plan.new()
|> Jido.Plan.add("weather_sf", Jido.Tools.Weather, %{location: "San Francisco"}, [])
|> Jido.Plan.add("weather_ny", Jido.Tools.Weather, %{location: "New York"}, [])
|> Jido.Plan.add("weather_la", Jido.Tools.Weather, %{location: "Los Angeles"}, [])
|> Jido.Plan.add("compare", MyApp.Actions.CompareWeather, %{}, 
    ["weather_sf", "weather_ny", "weather_la"])

{:ok, results} = Jido.Tools.ActionPlan.run(%{
  plan: parallel_plan
}, %{})
```

### Conditional Tool Usage

```elixir
defmodule MyApp.Actions.ConditionalFileOp do
  use Jido.Action,
    schema: [
      file_path: [type: :string, required: true],
      operation: [type: :atom, in: [:read, :delete], required: true]
    ]

  def run(params, context) do
    case params.operation do
      :read ->
        Jido.Tools.Files.ReadFile.run(%{path: params.file_path}, context)
      
      :delete ->
        Jido.Tools.Files.DeleteFile.run(%{path: params.file_path}, context)
    end
  end
end
```

## Error Handling with Tools

All built-in tools follow consistent error handling patterns:

```elixir
case Jido.Tools.Files.ReadFile.run(%{path: "/nonexistent.txt"}, %{}) do
  {:ok, result} -> 
    handle_success(result)
  
  {:error, %{type: :execution_error} = error} ->
    Logger.error("File operation failed: #{error.message}")
    handle_file_error(error)
  
  {:error, error} ->
    handle_other_error(error)
end
```

## AI Integration

All tools automatically work with AI systems:

```elixir
# Get tool definitions for AI
tools = [
  Jido.Tools.Weather.to_tool(),
  Jido.Tools.Files.ReadFile.to_tool(),
  Jido.Tools.Arithmetic.Add.to_tool()
]

# Tools are now available to AI for function calling
# The AI can invoke: weather, read_file, add
```

## Best Practices

### Tool Selection
- **Right Tool for Job**: Choose the most specific tool available
- **Composition**: Combine tools for complex operations
- **Error Handling**: Always handle tool errors gracefully
- **Context Propagation**: Pass context through tool chains

### Performance
- **Parallel Execution**: Use plans for independent operations
- **Resource Management**: Be mindful of file handles and network connections
- **Caching**: Cache expensive operations when appropriate
- **Timeouts**: Set appropriate timeouts for external tools

### Security
- **Path Validation**: Validate file paths in file operations
- **Input Sanitization**: Sanitize inputs to external services
- **Credential Management**: Handle API keys and tokens securely
- **Access Control**: Restrict tool usage based on user permissions

## Next Steps

**→ [AI Integration](ai-integration.md)** - Using tools with AI systems  
**→ [Instructions & Plans](instructions-plans.md)** - Composing tools into workflows  
**→ [Actions Guide](actions-guide.md)** - Creating your own tools

---
← [Security Guide](security.md) | **Next: [AI Integration](ai-integration.md)** →
