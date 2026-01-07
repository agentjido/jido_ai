# Quick Start Guide

This guide walks you through building your first useful Jido.AI agent step by step.

## Prerequisites

1. Elixir installed (1.14 or later)
2. An API key for an LLM provider (we'll use Anthropic/Claude)
3. Basic understanding of Elixir

---

## Step 1: Create a New Project

```bash
mix new my_ai_app --sup
cd my_ai_app
```

Update `mix.exs` to add dependencies:

```elixir
defp deps do
  [
    {:jido_ai, "~> 0.1"},
    {:req_llm, "~> 0.1"}
  ]
end
```

Install dependencies:

```bash
mix deps.get
```

---

## Step 2: Create Your First Action

Create `lib/my_ai_app/actions/calculator.ex`:

```elixir
defmodule MyAIApp.Actions.Calculator do
  @moduledoc """
  A calculator action for basic arithmetic operations.
  """

  use Jido.Action

  @impl true
  def name, do: "calculator"

  @impl true
  def description, do: "Performs basic arithmetic: add, subtract, multiply, divide"

  @impl true
  def schema do
    [
      operation: [
        type: :string,
        required: true,
        doc: "The operation: add, subtract, multiply, or divide"
      ],
      a: [
        type: :number,
        required: true,
        doc: "First number"
      ],
      b: [
        type: :number,
        required: true,
        doc: "Second number"
      ]
    ]
  end

  @impl true
  def run(params, _context) do
    operation = params["operation"]
    a = params["a"]
    b = params["b"]

    result = case operation do
      "add"      -> a + b
      "subtract" -> a - b
      "multiply" -> a * b
      "divide"   ->
        if b == 0, do: {:error, "Cannot divide by zero"}, else: a / b
      _          -> {:error, "Unknown operation: #{operation}"}
    end

    case result do
      {:error, msg} -> {:error, msg}
      value -> {:ok, %{result: value, operation: operation, a: a, b: b}}
    end
  end
end
```

---

## Step 3: Create Your First Agent

Create `lib/my_ai_app/agents/math_agent.ex`:

```elixir
defmodule MyAIApp.Agents.MathAgent do
  @moduledoc """
  An agent that can solve math problems.
  """

  use Jido.Agent,
    name: "math_agent",
    # Use ReAct strategy for reasoning + tool use
    strategy: {
      Jido.AI.Strategies.ReAct,
      model: "anthropic:claude-haiku-4-5",
      tools: [
        MyAIApp.Actions.Calculator
      ],
      max_iterations: 10
    }

  @impl true
  def system_prompt do
    """
    You are a helpful math assistant. You can solve mathematical problems
    by using the calculator tool when needed.

    Always show your work and explain your reasoning.
    """
  end
end
```

---

## Step 4: Start the Agent

Create `lib/my_ai_app/application.ex` (or update existing):

```elixir
defmodule MyAIApp.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Start your agent
      {MyAIApp.Agents.MathAgent, []}
    ]

    opts = [strategy: :one_for_one, name: MyAIApp.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
```

---

## Step 5: Use Your Agent

Start an IEx session:

```bash
iex -S mix
```

Now interact with your agent:

```elixir
# Get the agent process
{:ok, agent} = MyAIApp.Agents.MathAgent.get_pid()

# Ask a simple question
MyAIApp.Agents.MathAgent.chat(agent, "What is 15 plus 27?")
# => {:ok, %{answer: "15 plus 27 equals 42"}}

# Ask a more complex question
MyAIApp.Agents.MathAgent.chat(agent, """
  I have 5 apples. Someone gives me 12 more, then I eat 3.
  How many apples do I have left?
""")
# => The agent will reason: 5 + 12 = 17, then 17 - 3 = 14

# Multiple steps
MyAIApp.Agents.MathAgent.chat(agent, """
  What is 100 divided by 4, then multiplied by 3?
""")
# => The agent will use calculator twice: (100 / 4) * 3 = 75
```

---

## Complete Example: Adding More Tools

Let's add a search action and create a more capable agent.

Create `lib/my_ai_app/actions/weather.ex`:

```elixir
defmodule MyAIApp.Actions.Weather do
  @moduledoc """
  Gets weather information for a city.
  """

  use Jido.Action

  @impl true
  def name, do: "get_weather"

  @impl true
  def description, do: "Get the current weather for a city"

  @impl true
  def schema do
    [
      city: [
        type: :string,
        required: true,
        doc: "Name of the city"
      ]
    ]
  end

  @impl true
  def run(params, _context) do
    city = params["city"]

    # In a real app, call a weather API
    # For demo, return mock data
    weather_data = %{
      city: city,
      temperature: :rand.uniform(30) + 10,
      condition: Enum.random(["sunny", "cloudy", "rainy"]),
      humidity: :rand.uniform(50) + 30
    }

    {:ok, weather_data}
  end
end
```

Create a multi-purpose agent:

```elixir
defmodule MyAIApp.Agents.Assistant do
  @moduledoc """
  A general-purpose assistant.
  """

  use Jido.Agent,
    name: "assistant",
    strategy: {
      Jido.AI.Strategies.ReAct,
      model: "anthropic:claude-sonnet-4-20250514",
      tools: [
        MyAIApp.Actions.Calculator,
        MyAIApp.Actions.Weather
      ],
      max_iterations: 10
    }

  @impl true
  def system_prompt do
    """
    You are a helpful assistant. You can:
    - Solve math problems using the calculator
    - Check weather using get_weather

    Think step by step when answering questions.
    """
  end
end
```

Use it:

```elixir
{:ok, agent} = MyAIApp.Agents.Assistant.start_link()

# Math question
MyAIApp.Agents.Assistant.chat(agent, "What's 25 times 4?")

# Weather question
MyAIApp.Agents.Assistant.chat(agent, "What's the weather in Tokyo?")

# Combined question
MyAIApp.Agents.Assistant.chat(agent, """
  It's 20°C in London and 15°C cooler in Paris.
  If I need the temperature in Paris multiplied by 2, what would that be?
""")
# Agent will: 1) Get London weather (20°C), 2) Calculate 20-15=5,
# 3) Multiply 5*2=10, 4) Answer: 10°C
```

---

## Streaming Responses

For long responses, use streaming to get results in real-time:

```elixir
# Stream the response
MyAIApp.Agents.Assistant.chat_stream(agent, "Explain quantum physics")

# Or use the lower-level API
{:ok, agent} = MyAIApp.Agents.Assistant.start_link()

# Send a message and receive a stream
{:ok, stream} = MyAIApp.Agents.Assistant.call(agent, %{
  "message" => "Tell me a story"
})

# Process the stream
stream
|> Stream.each(fn chunk ->
  IO.write(chunk.delta)  # Write each token as it arrives
end)
|> Stream.run()
```

---

## Testing Your Agent

Create `test/my_ai_app/agents/math_agent_test.exs`:

```elixir
defmodule MyAIApp.Agents.MathAgentTest do
  use ExUnit.Case

  alias MyAIApp.Agents.MathAgent

  setup do
    {:ok, agent} = MathAgent.start_link()
    %{agent: agent}
  end

  test "solves simple addition", %{agent: agent} do
    assert {:ok, response} = MathAgent.chat(agent, "What is 5 plus 3?")
    assert response.answer =~ "8"
  end

  test "handles multi-step calculations", %{agent: agent} do
    assert {:ok, response} = MathAgent.chat(agent, """
      Start with 10, add 5, then multiply by 2.
    """)
    # (10 + 5) * 2 = 30
    assert response.answer =~ "30"
  end
end
```

Run tests:

```bash
mix test
```

---

## Tips for Success

### 1. Use Clear Descriptions

The LLM needs to understand what each tool does:

```elixir
# Good
def description, do: "Calculates the area of a rectangle given width and height"

# Bad
def description, do: "Does math"
```

### 2. Be Specific with Schemas

Help the agent use tools correctly:

```elixir
def schema do
  [
    city: [
      type: :string,
      required: true,
      doc: "Full city name, e.g., 'New York, NY'"
    ]
  ]
end
```

### 3. Set Appropriate Iterations

```elixir
# Simple tasks: fewer iterations
strategy: {Jido.AI.Strategies.ReAct, [
  max_iterations: 3
]}

# Complex tasks: more iterations
strategy: {Jido.AI.Strategies.ReAct, [
  max_iterations: 20
]}
```

### 4. Use the Right Model

```elixir
# Fast, cheap: Haiku
model: "anthropic:claude-haiku-4-5"

# Balanced: Sonnet
model: "anthropic:claude-sonnet-4-20250514"

# Most capable: Opus (when needed)
model: "anthropic:claude-opus-4-20250514"
```

---

## Next Steps

- [Strategies Guide](./03_strategies.md) - Learn about different reasoning algorithms
- [Tools & Actions Guide](./04_tools_actions.md) - Create more powerful tools
- [Examples](./05_examples.md) - See real-world agent examples
- [GEPA Guide](./06_gepa.md) - Optimize your prompts automatically
