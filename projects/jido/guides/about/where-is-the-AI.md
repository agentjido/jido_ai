# Where is the AI?

## Overview

Jido's core framework is purposely AI-agnostic. While Jido is excellent for building AI-powered agent systems, the core package doesn't include direct integrations with language models or other AI components.

## AI Integration

For AI capabilities, we provide a companion package called `jido_ai` that adds:

- Language model integrations (OpenAI, Anthropic, etc.)
- Embeddings and vector stores
- AI-specific actions and skills
- Prompt templates and management

## Usage Example

```elixir
# Add jido_ai to your dependencies
def deps do
  [
    {:jido, "~> 0.1.0"},
    {:jido_ai, "~> 0.1.0"} # For AI capabilities
  ]
end
```

## Why Separate?

This separation allows:

- Lighter core package for non-AI use cases
- Freedom to choose AI providers
- Easier testing and development
- Independent versioning of AI features

The core Jido framework focuses on agent fundamentals - signals, actions, and coordination. Add `jido_ai` when you need AI capabilities in your agent system.
