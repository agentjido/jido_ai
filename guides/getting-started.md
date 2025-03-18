# Getting Started with Jido AI

Welcome to **Jido AI**, an Elixir library that brings robust Large Language Model (LLM) capabilities, multi-modal generation, and structured data handling into your Elixir applications. This guide will walk you through the basic setup and show you how to run your first AI action using Jido AI.

---

## Overview

Jido AI leverages [Jido](https://hexdocs.pm/jido) (a workflow orchestration tool) and ties in various model providers—OpenAI, Anthropic, and more—to enable:

- **Text Generation & Chat Completion**: Interact with LLMs in your Elixir code.
- **Structured Data Generation**: Produce validated JSON objects or arrays using JSON schemas.
- **Multi-Modal Generation**: Create images and audio from text prompts.
- **Configurable Providers**: Switch between or extend providers at runtime.

---

## Installation

1. Add `jido_ai` to your `mix.exs`:

```elixir
def deps do
  [
    {:jido, "~> 1.1.0"}
    {:jido_ai, "~> 0.1.0"}
  ]
end
```

2. Fetch and compile:

```
mix deps.get
mix compile
```

3. Verify installation by running the test suite:

```
mix test
```
