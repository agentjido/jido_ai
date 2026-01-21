# Prompts

The `Jido.AI.Prompt` module provides struct-based prompt generation with support for templating, versioning, and LLM options. Prompts define the messages sent to LLMs and can include dynamic content through EEx or Liquid templates.

## Creating Prompts

### Simple Messages

Create a prompt with a single message using `Prompt.new/2`:

```elixir
alias Jido.AI.Prompt

# User message
prompt = Prompt.new(:user, "What is the capital of France?")

# System message
prompt = Prompt.new(:system, "You are a helpful geography assistant.")

# Assistant message
prompt = Prompt.new(:assistant, "The capital of France is Paris.")
```

### Multiple Messages

Create a prompt with multiple messages using `Prompt.new/1`:

```elixir
prompt = Prompt.new(%{
  messages: [
    %{role: :system, content: "You are a helpful assistant."},
    %{role: :user, content: "Hello!"},
    %{role: :assistant, content: "Hi there! How can I help you today?"},
    %{role: :user, content: "What's the weather like?"}
  ]
})
```

## Templating

Prompts support dynamic content through two templating engines: EEx and Liquid.

### EEx Templates

Use Elixir's built-in EEx templating with `@variable` syntax:

```elixir
prompt = Prompt.new(%{
  messages: [
    %{role: :system, content: "You are a <%= @assistant_type %>.", engine: :eex},
    %{role: :user, content: "My name is <%= @name %>. <%= @question %>", engine: :eex}
  ],
  params: %{
    assistant_type: "helpful coding assistant",
    name: "Alice",
    question: "Can you help me with Elixir?"
  }
})

# Render the prompt
messages = Prompt.render(prompt)
# => [
#   %{role: :system, content: "You are a helpful coding assistant."},
#   %{role: :user, content: "My name is Alice. Can you help me with Elixir?"}
# ]
```

### Liquid Templates

Use Liquid templating with `{{ variable }}` syntax:

```elixir
prompt = Prompt.new(%{
  messages: [
    %{role: :system, content: "You are a {{ assistant_type }}.", engine: :liquid},
    %{role: :user, content: "Hello {{ name }}!", engine: :liquid}
  ],
  params: %{
    assistant_type: "friendly assistant",
    name: "Bob"
  }
})

messages = Prompt.render(prompt)
# => [
#   %{role: :system, content: "You are a friendly assistant."},
#   %{role: :user, content: "Hello Bob!"}
# ]
```

### Override Parameters at Render Time

You can override parameters when rendering:

```elixir
prompt = Prompt.new(%{
  messages: [
    %{role: :user, content: "Hello <%= @name %>!", engine: :eex}
  ],
  params: %{name: "Default"}
})

# Override name at render time
messages = Prompt.render(prompt, %{name: "Override"})
# => [%{role: :user, content: "Hello Override!"}]
```

## Adding Messages

Add messages to an existing prompt:

```elixir
prompt = Prompt.new(:system, "You are a helpful assistant.")

# Add a user message
prompt = Prompt.add_message(prompt, :user, "Hello!")

# Add an assistant message
prompt = Prompt.add_message(prompt, :assistant, "Hi there!")

# Add a templated message
prompt = Prompt.add_message(prompt, :user, "My name is <%= @name %>", engine: :eex)
```

### System Message Rules

- Only one system message is allowed per prompt
- If present, the system message must be the first message

```elixir
# This will raise an error
prompt = Prompt.new(:user, "Hello")
Prompt.add_message(prompt, :system, "System message")  # Raises ArgumentError
```

## LLM Options

Configure LLM-specific options on prompts:

```elixir
prompt = Prompt.new(:user, "Generate a creative story")
  |> Prompt.with_temperature(0.8)
  |> Prompt.with_max_tokens(1000)
  |> Prompt.with_top_p(0.9)
  |> Prompt.with_stop(["END", "STOP"])
  |> Prompt.with_timeout(30_000)

# Get the rendered prompt with options
result = Prompt.render_with_options(prompt)
# => %{
#   messages: [%{role: :user, content: "Generate a creative story"}],
#   temperature: 0.8,
#   max_tokens: 1000,
#   top_p: 0.9,
#   stop: ["END", "STOP"],
#   timeout: 30000
# }
```

### Available Options

| Option | Description |
|--------|-------------|
| `temperature` | Controls randomness (0.0-2.0) |
| `max_tokens` | Maximum tokens to generate |
| `top_p` | Nucleus sampling threshold (0.0-1.0) |
| `stop` | Stop sequences (string or list) |
| `timeout` | Request timeout in milliseconds |

## Versioning

Prompts support versioning for tracking changes:

```elixir
# Create initial prompt
prompt = Prompt.new(:user, "Hello")

# Create a new version with changes
v2 = Prompt.new_version(prompt, fn p ->
  Prompt.add_message(p, :assistant, "Hi there!")
end)

v2.version  # => 2

# List all versions
Prompt.list_versions(v2)  # => [2, 1]

# Get a specific version
{:ok, v1} = Prompt.get_version(v2, 1)
length(v1.messages)  # => 1

# Compare versions
{:ok, diff} = Prompt.compare_versions(v2, 2, 1)
diff.added_messages  # => [%{role: :assistant, content: "Hi there!"}]
```

## Output Schema

Define expected output structure using NimbleOptions:

```elixir
schema = NimbleOptions.new!([
  name: [type: :string, required: true],
  age: [type: :integer, required: true]
])

prompt = Prompt.new(:user, "Generate a person")
  |> Prompt.with_output_schema(schema)

# Or create schema inline
prompt = Prompt.new(:user, "Generate a person")
  |> Prompt.with_new_output_schema([
    name: [type: :string, required: true],
    age: [type: :integer, required: true]
  ])
```

## Converting to Text

For debugging or APIs expecting plain text:

```elixir
prompt = Prompt.new(%{
  messages: [
    %{role: :system, content: "You are an assistant"},
    %{role: :user, content: "Hello"}
  ]
})

Prompt.to_text(prompt)
# => "[system] You are an assistant\n[user] Hello"
```

## Usage with Actions

Prompts are passed to actions like `ChatCompletion`:

```elixir
alias Jido.AI.Actions.ReqLlm.ChatCompletion
alias Jido.AI.{Model, Prompt}

{:ok, model} = Model.from({:openai, [model: "gpt-4o"]})

prompt = Prompt.new(%{
  messages: [
    %{role: :system, content: "You are a helpful assistant."},
    %{role: :user, content: "What is 2 + 2?"}
  ]
})

{:ok, result, _directives} = ChatCompletion.run(%{
  model: model,
  prompt: prompt
})

IO.puts(result.content)
```

## Prompt Struct

The `Jido.AI.Prompt` struct contains:

```elixir
%Jido.AI.Prompt{
  id: "unique-id",
  version: 1,
  history: [],
  messages: [%MessageItem{role: :user, content: "Hello", engine: :none}],
  params: %{},
  metadata: %{},
  options: [],
  output_schema: nil
}
```
