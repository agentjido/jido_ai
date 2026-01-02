defmodule Jido.AI do
  @moduledoc """
  AI integration layer for the Jido ecosystem.

  Jido.AI provides a unified interface for AI interactions, built on ReqLLM and
  integrated with the Jido action framework.

  ## Features

  - Text generation with any supported LLM provider
  - Structured output generation with schema validation
  - Streaming responses
  - Action-based AI workflows
  - Splode-based error handling

  ## Quick Start

      # Generate text
      {:ok, response} = Jido.AI.generate_text("anthropic:claude-haiku-4-5", "Hello!")

      # Generate structured output
      schema = Zoi.object(%{name: Zoi.string(), age: Zoi.integer()})
      {:ok, person} = Jido.AI.generate_object("openai:gpt-4", "Generate a person", schema)

  """
end
