# Getting Started with Jido Action

**Prerequisites**: Basic Elixir knowledge • Mix project setup

Jido Action is a composable action framework with AI integration for building autonomous agent systems and complex workflows. This guide will get you productive in 15 minutes.

## Installation

Add to your `mix.exs`:

```elixir
def deps do
  [{:jido_action, "~> 1.0"}]
end
```

Run `mix deps.get`.

## Your First Action

Create a simple email validator:

```elixir
defmodule MyApp.Actions.ValidateEmail do
  use Jido.Action,
    name: "validate_email",
    description: "Validates email format",
    schema: [
      email: [type: :string, required: true, doc: "Email to validate"]
    ]

  def run(%{email: email}, _context) do
    if String.contains?(email, "@") do
      {:ok, %{valid: true, email: String.downcase(email)}}
    else
      {:error, Jido.Action.Error.execution_error("Invalid email format")}
    end
  end
end
```

## Execute Your Action

```elixir
# Direct execution
{:ok, result} = MyApp.Actions.ValidateEmail.run(%{email: "USER@EXAMPLE.COM"}, %{})
# => {:ok, %{valid: true, email: "user@example.com"}}

# With execution engine (production-ready)
{:ok, result} = Jido.Exec.run(
  MyApp.Actions.ValidateEmail,
  %{email: "user@example.com"}, 
  %{},
  timeout: 5000,
  max_retries: 2
)
```

## Use Built-in Tools

Jido Action includes 25+ pre-built actions:

```elixir
# HTTP requests
{:ok, response} = Jido.Tools.ReqTool.new(
  url: "https://api.github.com/users/octocat"
).run(%{}, %{})

# File operations  
{:ok, _} = Jido.Tools.Files.WriteFile.run(%{
  path: "/tmp/test.txt",
  content: "Hello World!"
}, %{})

# Arithmetic
{:ok, result} = Jido.Tools.Arithmetic.Add.run(%{value: 5, amount: 3}, %{})
# => {:ok, %{result: 8}}
```

## Chain Actions Together

```elixir
# Sequential execution with data flow
{:ok, final_result} = Jido.Exec.Chain.chain([
  MyApp.Actions.ValidateEmail,
  MyApp.Actions.SendWelcomeEmail
], %{email: "user@example.com"}, %{user_id: "123"})
```

## Next Steps

**→ [Your Second Action](your-second-action.md)** - Add schemas, error handling, and tests  
**→ [Actions](actions-guide.md)** - Understand the framework architecture  
**→ [Built-in Tools](tools-reference.md)** - Explore all available tools

## Sample Repository

Clone the example project:
```bash
git clone https://github.com/agentjido/jido_action_examples
cd jido_action_examples
mix deps.get && mix test
```

---
**Next: [Your Second Action](your-second-action.md)** →
