# Tools and Actions Guide

Tools (also called Actions) are how your Jido.AI agent interacts with the world. This guide shows you how to create and use them.

## What is a Tool/Action?

A **Tool** or **Action** is a function your agent can call:
- Search a database
- Make an API call
- Perform calculations
- Read/write files
- Anything your code can do!

```
User Question
     ↓
Agent thinks: "I need to search"
     ↓
Agent calls: SearchTool.run(query="weather in Tokyo")
     ↓
Tool returns: {temperature: 20, condition: "sunny"}
     ↓
Agent uses result in answer
```

---

## Creating Your First Action

### Basic Template

```elixir
defmodule MyAction do
  @moduledoc """
  Brief description of what this action does.
  """

  use Jido.Action

  # 1. Give it a name
  @impl true
  def name, do: "my_action"

  # 2. Describe what it does (for the LLM)
  @impl true
  def description, do: "Does something useful"

  # 3. Define parameters
  @impl true
  def schema do
    [
      input: [
        type: :string,
        required: true,
        doc: "The input to process"
      ],
      option: [
        type: :integer,
        default: 10,
        doc: "Optional parameter"
      ]
    ]
  end

  # 4. Implement the logic
  @impl true
  def run(params, context) do
    input = params["input"]

    # Do your work here
    result = process(input)

    # Always return {:ok, result} or {:error, reason}
    {:ok, %{output: result}}
  end

  defp process(input), do: String.upcase(input)
end
```

---

## Common Action Patterns

### 1. API Call

```elixir
defmodule WeatherAction do
  @moduledoc """
  Gets weather from an API.
  """

  use Jido.Action

  @impl true
  def name, do: "get_weather"

  @impl true
  def description, do: "Get current weather for a city"

  @impl true
  def schema do
    [
      city: [
        type: :string,
        required: true,
        doc: "City name, e.g., 'London' or 'New York, NY'"
      ]
    ]
  end

  @impl true
  def run(params, _context) do
    city = params["city"]

    # Make API call
    case HTTPoison.get("https://api.weather.com/#{city}") do
      {:ok, %{body: body}} ->
        data = Jason.decode!(body)
        {:ok, %{
          city: city,
          temp: data["main"]["temp"],
          condition: data["weather"][0]["main"]
        }}

      {:error, reason} ->
        {:error, "Failed to get weather: #{inspect(reason)}"}
    end
  end
end
```

### 2. Database Query

```elixir
defmodule LookupUser do
  @moduledoc """
  Looks up a user in the database.
  """

  use Jido.Action

  @impl true
  def name, do: "lookup_user"

  @impl true
  def description, do: "Find a user by their email address"

  @impl true
  def schema do
    [
      email: [
        type: :string,
        required: true,
        doc: "User's email address"
      ]
    ]
  end

  @impl true
  def run(params, _context) do
    email = params["email"]

    case MyApp.Repo.get_by(MyApp.User, email: email) do
      nil ->
        {:error, "User not found"}

      user ->
        {:ok, %{
          id: user.id,
          name: user.name,
          email: user.email,
          role: user.role
        }}
    end
  end
end
```

### 3. Calculator

```elixir
defmodule Calculator do
  @moduledoc """
  Performs mathematical calculations.
  """

  use Jido.Action

  @impl true
  def name, do: "calculate"

  @impl true
  def description, do: """
  Evaluates mathematical expressions.
  Supports: +, -, *, /, parentheses
  Example: '2 + 2' or '(10 * 5) / 2'
  """

  @impl true
  def schema do
    [
      expression: [
        type: :string,
        required: true,
        doc: "Math expression to evaluate"
      ]
    ]
  end

  @impl true
  def run(params, _context) do
    expression = params["expression"]

    # Safe evaluation (only allow math operations)
    try do
      result = Code.eval_string(expression, [], __ENV__)
      {value, _} = result
      {:ok, %{result: value, expression: expression}}
    rescue
      e -> {:error, "Invalid expression: #{Exception.message(e)}"}
    end
  end
end
```

### 4. File Operations

```elixir
defmodule ReadFile do
  @moduledoc """
  Reads a file from disk.
  """

  use Jido.Action

  @impl true
  def name, do: "read_file"

  @impl true
  def description, do: "Read contents of a text file"

  @impl true
  def schema do
    [
      path: [
        type: :string,
        required: true,
        doc: "Path to the file"
      ],
      max_lines: [
        type: :integer,
        default: 100,
        doc: "Maximum lines to read"
      ]
    ]
  end

  @impl true
  def run(params, _context) do
    path = params["path"]
    max = params["max_lines"]

    # Security: only allow certain directories
    allowed_dir = "/home/user/documents/"

    if not String.starts_with?(path, allowed_dir) do
      {:error, "Access denied: path outside allowed directory"}
    else
      case File.read(path) do
        {:ok, content} ->
          lines = content
            |> String.split("\n")
            |> Enum.take(max)
            |> Enum.join("\n")

          {:ok, %{content: lines, line_count: Enum.count(lines)}}

        {:error, :enoent} ->
          {:error, "File not found: #{path}"}

        {:error, reason} ->
          {:error, "Failed to read file: #{inspect(reason)}"}
      end
    end
  end
end
```

### 5. Search

```elixir
defmodule WebSearch do
  @moduledoc """
  Searches the web for information.
  """

  use Jido.Action

  @impl true
  def name, do: "web_search"

  @impl true
  def description, do: "Search the web and return top results"

  @impl true
  def schema do
    [
      query: [
        type: :string,
        required: true,
        doc: "Search query"
      ],
      num_results: [
        type: :integer,
        default: 5,
        doc: "Number of results to return"
      ]
    ]
  end

  @impl true
  def run(params, _context) do
    query = params["query"]
    num = params["num_results"]

    # Call search API
    api_key = Application.get_env(:my_app, :search_api_key)

    case HTTPoison.post(
      "https://api.search.com/search",
      Jason.encode!(%{q: query, num: num}),
      [{"Authorization", "Bearer #{api_key}"}]
    ) do
      {:ok, %{body: body}} ->
        results = Jason.decode!(body)["results"]
        {:ok, %{results: results}}

      {:error, _reason} ->
        {:error, "Search failed"}
    end
  end
end
```

---

## Using Actions in Agents

### Single Action

```elixir
defmodule SimpleAgent do
  use Jido.Agent,
    name: "simple",
    strategy: {
      Jido.AI.Strategies.ReAct,
      model: "anthropic:claude-haiku-4-5",
      tools: [Calculator]  # Single tool
    }
end
```

### Multiple Actions

```elixir
defmodule CapableAgent do
  use Jido.Agent,
    name: "capable",
    strategy: {
      Jido.AI.Strategies.ReAct,
      model: "anthropic:claude-sonnet-4-20250514",
      tools: [
        Calculator,
        WebSearch,
        WeatherAction,
        ReadFile
      ]
    }
end
```

### With Configuration

```elixir
defmodule ConfiguredAgent do
  use Jido.Agent,
    name: "configured",
    strategy: {
      Jido.AI.Strategies.ReAct,
      model: "anthropic:claude-sonnet-4-20250514",
      tools: [
        {WeatherAction, api_key: System.get_env("WEATHER_API")},
        {DatabaseAction, repo: MyApp.Repo}
      ]
    }
end
```

---

## Action Best Practices

### 1. Clear Names

```elixir
# Bad
def name, do: "helper"

# Good
def name, do: "calculate_sum"
```

### 2. Descriptive Descriptions

```elixir
# Bad
def description, do: "Does math"

# Good
def description, do: """
Calculates the sum of two or more numbers.
Supports both integers and floating point numbers.
Example: 'add 5 and 3.5' returns 8.5
"""
```

### 3. Proper Schemas

```elixir
def schema do
  [
    # Always specify type
    amount: [
      type: :integer,
      # Mark required fields
      required: true,
      # Provide helpful docs
      doc: "Amount in dollars (must be positive)",
      # Add validation
      min: 0,
      max: 1_000_000
    ],
    # Use defaults for optional fields
    currency: [
      type: :string,
      default: "USD",
      doc: "Currency code"
    ]
  ]
end
```

### 4. Error Handling

```elixir
def run(params, _context) do
  try do
    result = do_work(params)
    {:ok, %{result: result}}
  rescue
    e in ArithmeticError ->
      {:error, "Math error: #{Exception.message(e)}"}

    e in RuntimeError ->
      {:error, "Runtime error: #{Exception.message(e)}"}

    e ->
      {:error, "Unexpected error: #{Exception.message(e)}"}
  end
end
```

### 5. Structured Results

```elixir
# Bad - unclear result
{:ok, "done"}

# Good - structured, clear
{:ok, %{
  status: "success",
  file: "document.txt",
  lines_written: 42,
  path: "/docs/document.txt"
}}
```

---

## Registering Actions

### Automatic (in Agent)

```elixir
# Tools listed in agent are auto-registered
tools: [Calculator, WeatherAction, Search]
```

### Manual Registration

```elixir
# Register at application startup
defmodule MyApp.Application do
  def start(_type, _args) do
    # Register actions globally
    Jido.AI.Tools.Registry.register(Calculator)
    Jido.AI.Tools.Registry.register(WeatherAction)
    Jido.AI.Tools.Registry.register(Search)

    # ... rest of startup
  end
end
```

### Check Registered Tools

```elixir
# List all tools
Jido.AI.Tools.Registry.list_all()
# => [{"calculator", :action, Calculator},
#     {"get_weather", :action, WeatherAction},
#     {"web_search", :action, Search}]

# Look up a specific tool
Jido.AI.Tools.Registry.get("calculator")
# => {:ok, {:action, Calculator}}
```

---

## Advanced: Context Access

Actions can access the agent's context:

```elixir
def run(params, context) do
  # Access agent state
  agent_id = context[:agent_id]

  # Access skill state (if using skills)
  skill_state = context[:my_skill_state]

  # Access request metadata
  request_id = context[:request_id]

  # Use context in your logic
  {:ok, %{agent: agent_id, result: "processed"}}
end
```

---

## Testing Actions

```elixir
defmodule CalculatorTest do
  use ExUnit.Case

  alias Calculator

  test "adds two numbers" do
    params = %{"expression" => "2 + 2"}
    assert {:ok, result} = Calculator.run(params, %{})
    assert result.result == 4
  end

  test "handles invalid expressions" do
    params = %{"expression" => "invalid"}
    assert {:error, _msg} = Calculator.run(params, %{})
  end

  test "validates required parameters" do
    params = %{}  # Missing expression
    assert {:error, _msg} = Calculator.run(params, %{})
  end
end
```

---

## Security Considerations

### 1. Sanitize Inputs

```elixir
def run(params, _context) do
  query = params["query"]

  # Sanitize to prevent injection
  sanitized = String.replace(query, ~r/[;<>]/, "")

  # Use sanitized input
  do_search(sanitized)
end
```

### 2. Validate Permissions

```elixir
def run(params, context) do
  user_id = context[:user_id]

  # Check permission
  if has_permission?(user_id, :delete_files) do
    delete_file(params["path"])
  else
    {:error, "Permission denied"}
  end
end
```

### 3. Rate Limiting

```elixir
def run(params, context) do
  # Check rate limit
  case RateLimiter.check(context[:user_id], @name) do
    :ok -> do_work(params)
    :rate_limited -> {:error, "Rate limit exceeded"}
  end
end
```

---

## Next Steps

- [Strategies Guide](./03_strategies.md) - Use actions in strategies
- [Examples](./05_examples.md) - See actions in real agents
- [Getting Started](./01_getting_started.md) - New to Jido.AI?
