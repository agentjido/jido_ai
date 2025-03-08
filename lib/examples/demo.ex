defmodule Jido.Examples.Demo do
  @moduledoc """
  A demo module showcasing how to use Jido.AI.Model and Jido.AI.Prompt.

  === Model Structure ===
  %Jido.AI.Model{
  max_retries: 0,
  max_tokens: 1024,
  temperature: 0.7,
  model_id: "claude-3-sonnet-20240229",
  api_key: <REDACTED>,
  base_url: "https://api.anthropic.com/v1",
  endpoints: [],
  description: "Anthropic Claude model",
  created: 1741260927,
  architecture: %Jido.AI.Model.Architecture{
    tokenizer: "unknown",
    modality: "text",
    instruct_type: nil
  },
  provider: :anthropic,
  name: "Anthropic claude-3-sonnet-20240229",
  id: "anthropic_claude-3-sonnet-20240229"
  }

  === Prompt Structure ===
  %Jido.AI.Prompt{
  metadata: %{},
  params: %{
    language: "Elixir",
    assistant_type: "helpful programming assistant",
    specialty: "software architecture and best practices",
    style: "clear and concise"
  },
  messages: [
    %Jido.AI.Prompt.MessageItem{
      name: nil,
      engine: :eex,
      content: "You are a <%= @assistant_type %> specializing in <%= @specialty %>.\nYour communication style is <%= @style %>.\n",
      role: :system
    },
    %Jido.AI.Prompt.MessageItem{
      name: nil,
      engine: :none,
      content: "What are the key principles of functional programming?",
      role: :user
    },
    %Jido.AI.Prompt.MessageItem{
      name: nil,
      engine: :none,
      content: "The key principles include immutability, pure functions, and composition over inheritance. Would you like me to elaborate on any of these?",
      role: :assistant
    },
    %Jido.AI.Prompt.MessageItem{
      name: nil,
      engine: :none,
      content: "Tell me more about pure functions.",
      role: :user
    },
    %Jido.AI.Prompt.MessageItem{
      name: nil,
      engine: :none,
      content: "Pure functions are functions that, given the same input, always return the same output and have no side effects. They don't modify external state or depend on it.",
      role: :assistant
    },
    %Jido.AI.Prompt.MessageItem{
      name: nil,
      engine: :eex,
      content: "Can you give me an example of a pure function in <%= @language %>?",
      role: :user
    }
  ],
  history: [],
  version: 1,
  id: "01956b3b-3135-746d-a4d5-6eadfc035fe2"
  }

  === Rendered Messages ===
  [
  %{
    role: :system,
    content: "You are a helpful programming assistant specializing in software architecture and best practices.\nYour communication style is clear and concise.\n"
  },
  %{
    role: :user,
    content: "What are the key principles of functional programming?"
  },
  %{
    role: :assistant,
    content: "The key principles include immutability, pure functions, and composition over inheritance. Would you like me to elaborate on any of these?"
  },
  %{role: :user, content: "Tell me more about pure functions."},
  %{
    role: :assistant,
    content: "Pure functions are functions that, given the same input, always return the same output and have no side effects. They don't modify external state or depend on it."
  },
  %{
    role: :user,
    content: "Can you give me an example of a pure function in Elixir?"
  }
  ]

  === Text Format ===
  [system] You are a helpful programming assistant specializing in software architecture and best practices.
  Your communication style is clear and concise.

  [user] What are the key principles of functional programming?
  [assistant] The key principles include immutability, pure functions, and composition over inheritance. Would you like me to elaborate on any of these?
  [user] Tell me more about pure functions.
  [assistant] Pure functions are functions that, given the same input, always return the same output and have no side effects. They don't modify external state or depend on it.
  [user] Can you give me an example of a pure function in Elixir?
  """

  alias Jido.AI.Model
  alias Jido.AI.Prompt

  def run do
    # 1. Define a model using shorthand tuple format
    {:ok, model} =
      Model.from(
        {:anthropic,
         [
           model_id: "claude-3-sonnet-20240229",
           temperature: 0.7,
           max_tokens: 1024
         ]}
      )

    # 2. Create a sophisticated prompt with history and template substitution
    prompt =
      Prompt.new(%{
        messages: [
          # System message with template substitution
          %{
            role: :system,
            content: """
            You are a <%= @assistant_type %> specializing in <%= @specialty %>.
            Your communication style is <%= @style %>.
            """,
            engine: :eex
          },
          # Historical messages
          %{
            role: :user,
            content: "What are the key principles of functional programming?",
            engine: :none
          },
          %{
            role: :assistant,
            content:
              "The key principles include immutability, pure functions, and composition over inheritance. Would you like me to elaborate on any of these?",
            engine: :none
          },
          %{
            role: :user,
            content: "Tell me more about pure functions.",
            engine: :none
          },
          %{
            role: :assistant,
            content:
              "Pure functions are functions that, given the same input, always return the same output and have no side effects. They don't modify external state or depend on it.",
            engine: :none
          },
          # Current message with template substitution
          %{
            role: :user,
            content: "Can you give me an example of a pure function in <%= @language %>?",
            engine: :eex
          }
        ],
        params: %{
          assistant_type: "helpful programming assistant",
          specialty: "software architecture and best practices",
          style: "clear and concise",
          language: "Elixir"
        }
      })

    # 3. Inspect the model and prompt
    IO.puts("\n=== Model Structure ===")
    IO.inspect(model, pretty: true, limit: :infinity)

    IO.puts("\n=== Prompt Structure ===")
    IO.inspect(prompt, pretty: true, limit: :infinity)

    # 4. Render the prompt to see the final messages
    IO.puts("\n=== Rendered Messages ===")
    rendered_messages = Prompt.render(prompt)
    IO.inspect(rendered_messages, pretty: true, limit: :infinity)

    # 5. Convert to text format
    IO.puts("\n=== Text Format ===")
    text_format = Prompt.to_text(prompt)
    IO.puts(text_format)
  end
end
