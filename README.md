# Jido AI

**Intelligent Agent Framework for Elixir**

Jido AI is a comprehensive framework for building sophisticated AI agents and workflows in Elixir. It extends the [Jido](https://github.com/agentjido/jido) framework with powerful LLM capabilities, advanced reasoning techniques, and stateful conversation management.

## Features

- **Multi-Provider Support**: Access 57+ LLM providers through ReqLLM (OpenAI, Anthropic, Google, Mistral, and more)
- **Advanced Reasoning**: Chain-of-Thought, ReAct, Tree-of-Thoughts, Self-Consistency, GEPA
- **Structured Prompts**: Template-based prompts with EEx and Liquid support
- **Tool Integration**: Function calling with automatic schema conversion
- **Conversation Management**: Stateful multi-turn conversations with ETS storage
- **Context Window Management**: Automatic token counting and truncation strategies

## Installation

Add `jido_ai` to your `mix.exs` dependencies:

```elixir
def deps do
  [
    {:jido_ai, "~> 0.5.3"}
  ]
end
```

## Quick Start

```elixir
alias Jido.AI.{Model, Prompt}
alias Jido.AI.Actions.ReqLlm.ChatCompletion

# Create a model
{:ok, model} = Model.from({:anthropic, [model: "claude-3-5-sonnet"]})

# Create a prompt
prompt = Prompt.new(:user, "What is the capital of France?")

# Get a response
{:ok, result} = ChatCompletion.run(%{model: model, prompt: prompt}, %{})
IO.puts(result.content)
```

## Documentation

### User Guides

Learn how to use Jido AI in your applications:

| Guide | Description |
|-------|-------------|
| [Getting Started](guides/user/getting-started.md) | Installation, configuration, and first steps |
| [Models](guides/user/models.md) | Working with LLM models and providers |
| [Prompts](guides/user/prompts.md) | Creating and templating prompts |
| [Configuration](guides/user/configuration.md) | API keys and settings management |
| [Chat Completion](guides/user/chat-completion.md) | Basic and advanced chat completions |
| [Conversations](guides/user/conversations.md) | Multi-turn stateful conversations |

### Runners (Advanced Reasoning)

Implement sophisticated reasoning strategies:

| Runner | Description | Accuracy Gain |
|--------|-------------|---------------|
| [Overview](guides/user/runners/overview.md) | Introduction to runners | - |
| [Chain of Thought](guides/user/runners/chain-of-thought.md) | Step-by-step reasoning | +8-15% |
| [ReAct](guides/user/runners/react.md) | Reasoning with tool use | +27% |
| [Self-Consistency](guides/user/runners/self-consistency.md) | Multiple paths with voting | +17.9% |
| [Tree of Thoughts](guides/user/runners/tree-of-thoughts.md) | Tree search exploration | +74% |
| [GEPA](guides/user/runners/gepa.md) | Evolutionary prompt optimization | +10-19% |

### Developer Guides

Understand the internals for extending Jido AI:

| Guide | Description |
|-------|-------------|
| [Architecture](guides/developer/architecture.md) | System architecture and components |
| [Model System](guides/developer/model-system.md) | Model creation, registry, and discovery |
| [Prompt System](guides/developer/prompt-system.md) | Prompt structs, templating, versioning |
| [Actions System](guides/developer/actions-system.md) | Jido Actions and tool integration |
| [Runners System](guides/developer/runners-system.md) | Runner implementations and patterns |
| [Data Flow](guides/developer/data-flow.md) | Request lifecycle and data transformations |

## Supported Providers

Jido AI supports 57+ providers through ReqLLM:

| Provider | Example Models |
|----------|----------------|
| **Anthropic** | Claude 3.5 Sonnet, Claude 3 Opus |
| **OpenAI** | GPT-4o, GPT-4 Turbo |
| **Google** | Gemini 1.5 Pro, Gemini 1.5 Flash |
| **Mistral** | Mistral Large, Mixtral 8x7B |
| **Groq** | Llama 3.1 70B |
| **Cohere** | Command R+ |
| **Local** | Ollama, LM Studio |

See the [Models Guide](guides/user/models.md) for complete provider documentation.

## Configuration

Set API keys via environment variables:

```bash
export ANTHROPIC_API_KEY="sk-..."
export OPENAI_API_KEY="sk-..."
export GOOGLE_API_KEY="..."
```

Or configure in your application:

```elixir
config :jido_ai, :keyring, %{
  anthropic_api_key: "sk-...",
  openai_api_key: "sk-..."
}
```

See the [Configuration Guide](guides/user/configuration.md) for details.

## API Documentation

Full API documentation is available at [HexDocs](https://hexdocs.pm/jido_ai).

Generate documentation locally:

```bash
mix docs
open doc/index.html
```

## Resources

- [GitHub Repository](https://github.com/agentjido/jido_ai)
- [HexDocs](https://hexdocs.pm/jido_ai)
- [Jido Framework](https://github.com/agentjido/jido)
- [ReqLLM](https://hexdocs.pm/req_llm)

## License

MIT License - see LICENSE for details.
