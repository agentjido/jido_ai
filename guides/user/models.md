# Models

Models in Jido AI represent LLM configurations that specify which provider and model to use for AI operations. The `Jido.AI.Model` module provides functions for creating and validating model configurations.

## Creating Models

The primary entry point for creating models is `Jido.AI.Model.from/1`. This function accepts multiple input formats and returns a `ReqLLM.Model` struct.

### From Provider Tuple

The most common way to create a model is with a provider tuple:

```elixir
# Anthropic Claude
{:ok, model} = Jido.AI.Model.from({:anthropic, [model: "claude-3-5-sonnet-20241022"]})

# OpenAI GPT-4
{:ok, model} = Jido.AI.Model.from({:openai, [model: "gpt-4o"]})

# Google Gemini
{:ok, model} = Jido.AI.Model.from({:google, [model: "gemini-pro"]})

# Mistral
{:ok, model} = Jido.AI.Model.from({:mistral, [model: "mistral-large-latest"]})
```

### From String Specification

Models can also be created from a string in `provider:model` format:

```elixir
{:ok, model} = Jido.AI.Model.from("openai:gpt-4o")
{:ok, model} = Jido.AI.Model.from("anthropic:claude-3-5-haiku")
```

### Pass-through

If you already have a `ReqLLM.Model` struct, it passes through unchanged:

```elixir
existing_model = %ReqLLM.Model{provider: :openai, model: "gpt-4"}
{:ok, model} = Jido.AI.Model.from(existing_model)
# model is the same as existing_model
```

## Model Options

When creating models from tuples, you must specify at least the `:model` option:

```elixir
{:ok, model} = Jido.AI.Model.from({:anthropic, [
  model: "claude-3-5-sonnet-20241022"
]})
```

Additional options can be passed for specific configurations:

```elixir
{:ok, model} = Jido.AI.Model.from({:openai, [
  model: "gpt-4o",
  temperature: 0.3,
  max_tokens: 2048
]})
```

## Supported Providers

Jido AI supports 57+ providers through ReqLLM integration. Common providers include:

| Provider | Key | Example Model |
|----------|-----|---------------|
| OpenAI | `:openai` | `gpt-4o`, `gpt-4o-mini` |
| Anthropic | `:anthropic` | `claude-3-5-sonnet-20241022` |
| Google | `:google` | `gemini-pro`, `gemini-1.5-pro` |
| Mistral | `:mistral` | `mistral-large-latest` |
| Azure OpenAI | `:azure` | deployment-specific |
| Ollama | `:ollama` | `llama3.2`, `mistral` |
| OpenRouter | `:openrouter` | Various |

For a complete list, see the ReqLLM documentation.

## Model Struct Fields

The `ReqLLM.Model` struct contains:

```elixir
%ReqLLM.Model{
  provider: :anthropic,
  model: "claude-3-5-sonnet-20241022",
  max_tokens: 1024,
  capabilities: %{tool_call: true, reasoning: false},
  modalities: %{input: [:text], output: [:text]},
  cost: %{input: 3.0, output: 15.0}
}
```

## Default Models

The `Jido.AI` module provides helpers for getting default model names:

```elixir
# Get default model name for a provider
Jido.AI.model_name(:openai)     # => "gpt-4o"
Jido.AI.model_name(:anthropic)  # => "claude-3-5-sonnet-20241022"
Jido.AI.model_name(:azure)      # => "gpt-4o"
Jido.AI.model_name(:ollama)     # => "llama3.2"
```

## Error Handling

Model creation returns `{:ok, model}` on success or `{:error, reason}` on failure:

```elixir
case Jido.AI.Model.from({:anthropic, [model: "claude-3-5-sonnet"]}) do
  {:ok, model} ->
    # Use the model
    IO.inspect(model)

  {:error, reason} ->
    # Handle the error
    IO.puts("Failed to create model: #{reason}")
end
```

Common errors:
- Missing `:model` option
- Invalid provider
- Malformed string specification

## Usage with Actions

Models are passed to actions like `ChatCompletion`:

```elixir
alias Jido.AI.Actions.ReqLlm.ChatCompletion
alias Jido.AI.{Model, Prompt}

{:ok, model} = Model.from({:openai, [model: "gpt-4o"]})
prompt = Prompt.new(:user, "Hello!")

{:ok, result, _directives} = ChatCompletion.run(%{
  model: model,
  prompt: prompt
})
```

## Usage with Runners

Models can be configured for runners like Chain-of-Thought:

```elixir
defmodule MyAgent do
  use Jido.Agent,
    name: "my_agent",
    runner: Jido.AI.Runner.ChainOfThought,
    actions: [MyAction]
end

{:ok, agent} = MyAgent.new()
{:ok, updated_agent, directives} = Jido.AI.Runner.ChainOfThought.run(agent,
  model: "gpt-4o"  # Model name as string
)
```
