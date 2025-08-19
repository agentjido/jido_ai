# Jido AI

Jido AI is an extension of the Jido framework for building AI Agents and Workflows in Elixir. At present, it provides a single action for interacting with Anthropic's Claude models via the Instructor library.

## Installation

> **Note:** You must install `instructor` from GitHub until a new version is released. Hex does not yet have a release of `instructor` that supports the `Instructor.Adapters.Anthropic` adapter.

```elixir
def deps do
  [
    {:jido, "~> 1.0.0"},
    {:jido_ai, "~> 1.0.0"},

    # Must install from github until a new version is released
    {:instructor, github: "thmsmlr/instructor_ex"}
  ]
end
```

## Configuration

You will need to properly configure the `Instructor` library to use the Anthropic adapter:

```elixir
# config/config.exs
config :instructor,
  adapter: Instructor.Adapters.Anthropic,
  anthropic: [
    api_key: System.get_env("ANTHROPIC_API_KEY")
  ]
```

## Playground

Jido AI includes a built-in chat interface for testing and showcasing streaming capabilities:

```bash
# Start the playground with default settings
mix jido.ai.playground

# Or use the alias
mix playground

# Specify a different model
mix playground --model anthropic:claude-3.5-sonnet

# Run on a different port
mix playground --port 4000
```

This launches a Phoenix LiveView chat interface at http://localhost:4001 where you can interact with AI models using Jido AI's `stream_text` functionality. The playground provides a clean, responsive chat interface that demonstrates real-time streaming responses.

## Supported Providers

Jido AI supports multiple LLM providers:

- Anthropic (Claude models)
- OpenAI (GPT models)
- OpenRouter (proxy for multiple models)
- Cloudflare (Workers AI models)
- Google (Gemini models)

### Using Google Gemini

To use Google's Gemini models with the OpenAI-compatible API:

```elixir
# Set your Google API key
Jido.AI.Keyring.set_session_value(:google_api_key, "your_gemini_api_key")

# Create a model using the Google provider
{:ok, model} = Jido.AI.Model.from({:google, [model: "gemini-2.0-flash"]})

# Use the model with the OpenaiEx action
result = Jido.AI.Actions.OpenaiEx.run(
  %{
    model: model,
    messages: [
      %{role: :user, content: "Tell me about Elixir programming language"}
    ],
    temperature: 0.7
  },
  %{}
)

# Handle the result
case result do
  {:ok, %{content: content, tool_results: _}} ->
    IO.puts("Response: #{content}")
  {:error, %{reason: reason, details: details}} ->
    IO.puts("Error: #{reason} - #{inspect(details)}")
end
```

You can also set the Google API key using environment variables:

```
GOOGLE_API_KEY=your_gemini_api_key
```

## Prompt and Message Handling

Jido AI provides a robust system for handling prompts and messages when interacting with LLMs.

### MessageItem

The `Jido.AI.Prompt.MessageItem` module is used to represent messages in conversations with LLMs. It supports:

- Basic text messages with different roles (user, assistant, system, function)
- Rich content including images and files
- Template-based messages using EEx

```elixir
alias Jido.AI.Prompt.MessageItem

# Create a simple user message
user_msg = MessageItem.new(%{role: :user, content: "Hello"})

# Create a system message
system_msg = MessageItem.new(%{role: :system, content: "You are a helpful assistant"})

# Create a message with rich content (image)
rich_msg = MessageItem.new_multipart(:user, [
  MessageItem.text_part("Check out this image:"),
  MessageItem.image_part("https://example.com/image.jpg")
])

# Create a message with a template
template_msg = MessageItem.new(%{
  role: :system,
  content: "You are a <%= @assistant_type %>",
  engine: :eex
})
```

For more details on MessageItem usage, refer to the documentation.

## Example

Here's how to use Jido AI with Jido.Exec to get structured information about US politicians. See the [examples/politician.ex](examples/politician.ex) for more a full example.

```elixir
# Define a simple workflow
defmodule JidoAi.Examples.Politician do
  defmodule Schema do
    use Ecto.Schema
    use Instructor
    @primary_key false
    embedded_schema do
      field(:first_name, :string)
      field(:last_name, :string)

      embeds_many :offices_held, Office, primary_key: false do
        field(:office, Ecto.Enum,
          values: [:president, :vice_president, :governor, :congress, :senate]
        )

        field(:from_date, :date)
        field(:to_date, :date)
      end
    end
  end

  use Jido.Action,
    name: "politician",
    description: "A description of United States Politicians and the offices that they held",
    schema: [
      query: [type: :string, required: true, doc: "The query to search for"]
    ]

  def run(params, _context) do
    # Run the Anthropic ChatCompletion action
    JidoAi.Actions.Anthropic.ChatCompletion.run(
      %{
        model: "claude-3-5-haiku-latest",
        messages: [
          %{
            role: "user",
            content: params.query
          }
        ],
        response_model: Schema,
        temperature: 0.5,
        max_tokens: 1000
      },
      %{}
    )
    |> case do
      {:ok, %{result: politician}} -> {:ok, %{result: politician}}
      {:error, reason} -> {:error, reason}
    end
  end
end

# Run the workflow
iex> {:ok, result} = Jido.Exec.run(JidoAi.Examples.Politician, %{query: "Tell me about Barack Obama's political career"})
iex> result.result
%JidoAi.Examples.Politician.Schema{
  first_name: "Barack",
  last_name: "Obama",
  offices_held: [
    %JidoAi.Examples.Politician.Schema.Office{
      office: :senate,
      from_date: ~D[2005-01-03],
      to_date: ~D[2008-11-16]
    },
    %JidoAi.Examples.Politician.Schema.Office{
      office: :president,
      from_date: ~D[2009-01-20],
      to_date: ~D[2017-01-20]
    }
  ]
}
```

The example demonstrates how JidoAi can:

- Write Actions that can wrap other Actions
- Use Jido.Exec to orchestrate AI operations
- Parse natural language queries about politicians
- Return structured data using Ecto schemas
- Handle complex nested data structures
- Provide type validation through Ecto's type system

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/jido_ai>.

## LLM Keyring

The Jido.AI application includes a Keyring system that manages API keys for various LLM providers. The Keyring is a singleton GenServer that helps to manage LLM keys for convenience, not for security.

### Key Sources

Keys are loaded with the following priority:

1. Environment variables (highest priority)
2. Application environment
3. Default values (lowest priority)

### Session-based Keys

Keys can also be set on a per-session (per-process) basis. This allows different parts of your application to use different API keys without affecting other processes.

### Usage

```elixir
# Get a key (checks session keys first, then environment keys)
api_key = Jido.AI.Keyring.get_key(:anthropic)

# Get only the environment-level key
env_key = Jido.AI.Keyring.get_env_key(:anthropic)

# Set a session-specific key (only affects the current process)
Jido.AI.Keyring.set_session_key(:anthropic, "my_session_key")

# Clear a session key
Jido.AI.Keyring.clear_session_key(:anthropic)

# Clear all session keys for the current process
Jido.AI.Keyring.clear_all_session_keys()

# Check if a key is valid (non-nil and non-empty)
Jido.AI.Keyring.has_valid_key?(api_key)

# Test if a key is valid by making an API request
Jido.AI.Keyring.test_key(:anthropic, api_key)
```

### Configuration

You can configure keys in your `config.exs` file:

```elixir
config :jido_ai, :instructor,
  anthropic: [
    api_key: "your_anthropic_key"
  ]

config :jido_ai, :openai,
  api_key: "your_openai_key"
```

Or using environment variables:

```
ANTHROPIC_API_KEY=your_anthropic_key
OPENAI_API_KEY=your_openai_key
```

Environment variables take precedence over application configuration.