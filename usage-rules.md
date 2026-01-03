# Jido.AI Usage Rules

Jido.AI provides AI integration for the Jido ecosystem, built on ReqLLM and jido_action.

## Core Usage

### Text Generation

```elixir
# Via Jido.AI facade
{:ok, response} = Jido.AI.generate_text("anthropic:claude-haiku-4-5", "Hello!")

# Via Action execution
{:ok, result} = Jido.Exec.run(Jido.AI.Actions.GenerateText, %{
  model: "openai:gpt-4o-mini",
  prompt: "Explain recursion"
})
```

### Structured Output

```elixir
schema = Zoi.object(%{
  name: Zoi.string(),
  age: Zoi.integer() |> Zoi.min(0)
})

{:ok, person} = Jido.AI.generate_object("openai:gpt-4", "Generate a person", schema)
```

### Streaming

```elixir
{:ok, stream} = Jido.AI.stream_text("anthropic:claude-haiku-4-5", "Write a story")
stream |> Stream.each(&IO.write(&1.text)) |> Stream.run()
```

## Action Patterns

### Creating AI Actions

```elixir
defmodule MyApp.Actions.Summarize do
  use Jido.Action,
    name: "summarize",
    description: "Summarizes text content",
    schema: Zoi.object(%{
      text: Zoi.string() |> Zoi.min_length(10),
      model: Zoi.string() |> Zoi.optional() |> Zoi.default("anthropic:claude-haiku-4-5")
    })

  def run(params, _context) do
    Jido.AI.generate_text(params.model, """
    Summarize the following text concisely:

    #{params.text}
    """)
  end
end
```

## Error Handling

```elixir
case Jido.AI.generate_text("anthropic:claude-haiku-4-5", prompt) do
  {:ok, response} -> 
    {:ok, response.text}
  {:error, %Jido.AI.Error.RateLimit{retry_after: seconds}} -> 
    {:retry, seconds}
  {:error, %Jido.AI.Error.Authentication{}} -> 
    {:error, :auth_failed}
  {:error, error} -> 
    {:error, error}
end
```

## Model Specification

```elixir
# String format
Jido.AI.generate_text("anthropic:claude-haiku-4-5", "Hello")

# With options
Jido.AI.generate_text("openai:gpt-4", "Hello", temperature: 0.7, max_tokens: 100)
```
