# Conversations

The `Jido.AI.Conversation.Manager` provides stateful multi-turn conversation support with ETS-backed storage. It tracks message history and conversation metadata for building chat applications.

## Overview

The Conversation Manager maintains conversation state in ETS, allowing you to:
- Create conversations with specific models
- Add and retrieve messages
- Track conversation metadata
- Manage multiple concurrent conversations

Note: Conversations are stored in ETS and do not persist across application restarts.

## Basic Usage

```elixir
alias Jido.AI.Conversation.Manager
alias Jido.AI.Model

# Create a model
{:ok, model} = Model.from({:openai, [model: "gpt-4o"]})

# Create a conversation
{:ok, conv_id} = Manager.create(model)

# Add messages
:ok = Manager.add_message(conv_id, :user, "Hello!")
:ok = Manager.add_message(conv_id, :assistant, "Hi there! How can I help?")
:ok = Manager.add_message(conv_id, :user, "What's the weather like?")

# Get message history
{:ok, messages} = Manager.get_messages(conv_id)

# Clean up when done
:ok = Manager.delete(conv_id)
```

## Creating Conversations

### Basic Creation

```elixir
{:ok, model} = Model.from({:openai, [model: "gpt-4o"]})
{:ok, conv_id} = Manager.create(model)
```

### With System Prompt

```elixir
{:ok, conv_id} = Manager.create(model,
  system_prompt: "You are a helpful assistant specialized in Elixir programming."
)
```

### With Options

```elixir
{:ok, conv_id} = Manager.create(model,
  system_prompt: "You are a helpful assistant.",
  options: %{
    temperature: 0.5,
    max_tokens: 2000
  }
)
```

## Adding Messages

### Basic Messages

```elixir
# User message
:ok = Manager.add_message(conv_id, :user, "Hello!")

# Assistant message
:ok = Manager.add_message(conv_id, :assistant, "Hi! How can I help?")
```

### With Tool Calls

```elixir
:ok = Manager.add_message(conv_id, :assistant, "I'll check the weather.",
  tool_calls: [
    %{name: "get_weather", arguments: %{"city" => "Tokyo"}}
  ]
)
```

### Tool Results

```elixir
:ok = Manager.add_message(conv_id, :tool, "Temperature: 72°F, Sunny",
  tool_call_id: "call_123"
)
```

## Retrieving Messages

### Get All Messages

```elixir
{:ok, messages} = Manager.get_messages(conv_id)

Enum.each(messages, fn msg ->
  IO.puts("[#{msg.role}] #{msg.content}")
end)
```

### Get Messages for LLM API

Format messages for direct use with LLM APIs:

```elixir
{:ok, formatted} = Manager.get_messages_for_llm(conv_id)
# => [
#   %{role: :system, content: "You are helpful."},
#   %{role: :user, content: "Hello!"},
#   %{role: :assistant, content: "Hi!"}
# ]
```

## Conversation State

### Get Full Conversation

```elixir
{:ok, conversation} = Manager.get(conv_id)

IO.inspect(conversation.model)
IO.inspect(conversation.messages)
IO.inspect(conversation.options)
```

### Get Metadata Only

```elixir
{:ok, metadata} = Manager.get_metadata(conv_id)
# => %{
#   id: "abc123...",
#   message_count: 5,
#   created_at: ~U[2024-01-15 10:30:00Z],
#   updated_at: ~U[2024-01-15 10:35:00Z],
#   options: %{temperature: 0.7, max_tokens: 1024}
# }
```

## Managing Conversations

### Update Options

```elixir
:ok = Manager.update_options(conv_id, %{
  temperature: 0.3,
  max_tokens: 500
})
```

### Check Existence

```elixir
if Manager.exists?(conv_id) do
  IO.puts("Conversation exists")
else
  IO.puts("Conversation not found")
end
```

### List All Conversations

```elixir
conversation_ids = Manager.list()
IO.puts("Active conversations: #{length(conversation_ids)}")
```

### Delete Conversation

```elixir
:ok = Manager.delete(conv_id)
```

## Complete Chat Example

```elixir
alias Jido.AI.{Model, Conversation.Manager}
alias Jido.AI.Actions.ReqLlm.ChatCompletion

# Setup
{:ok, model} = Model.from({:openai, [model: "gpt-4o"]})
{:ok, conv_id} = Manager.create(model,
  system_prompt: "You are a helpful coding assistant."
)

# Chat loop
defmodule ChatLoop do
  def chat(conv_id, model) do
    user_input = IO.gets("> ") |> String.trim()

    if user_input == "quit" do
      IO.puts("Goodbye!")
      Manager.delete(conv_id)
    else
      # Add user message
      :ok = Manager.add_message(conv_id, :user, user_input)

      # Get formatted messages
      {:ok, messages} = Manager.get_messages_for_llm(conv_id)

      # Create prompt from messages
      prompt = Jido.AI.Prompt.new(%{
        messages: messages
      })

      # Get response
      case ChatCompletion.run(%{model: model, prompt: prompt}) do
        {:ok, result, _} ->
          IO.puts("Assistant: #{result.content}")

          # Add assistant response to history
          :ok = Manager.add_message(conv_id, :assistant, result.content)

        {:error, reason} ->
          IO.puts("Error: #{inspect(reason)}")
      end

      # Continue loop
      chat(conv_id, model)
    end
  end
end

ChatLoop.chat(conv_id, model)
```

## Error Handling

### Conversation Not Found

```elixir
case Manager.get_messages("invalid_id") do
  {:ok, messages} ->
    IO.inspect(messages)

  {:error, :conversation_not_found} ->
    IO.puts("Conversation does not exist")
end
```

### Handle All Operations

```elixir
with {:ok, model} <- Model.from({:openai, [model: "gpt-4o"]}),
     {:ok, conv_id} <- Manager.create(model),
     :ok <- Manager.add_message(conv_id, :user, "Hello"),
     {:ok, messages} <- Manager.get_messages(conv_id) do
  IO.puts("Success! #{length(messages)} messages")
else
  {:error, reason} ->
    IO.puts("Error: #{inspect(reason)}")
end
```

## Conversation Structure

The internal conversation structure:

```elixir
%Jido.AI.Conversation.Manager.Conversation{
  id: "abc123...",
  model: %ReqLLM.Model{...},
  messages: [
    %Message{role: :system, content: "You are helpful."},
    %Message{role: :user, content: "Hello!"},
    %Message{role: :assistant, content: "Hi!"}
  ],
  options: %{
    temperature: 0.7,
    max_tokens: 1024
  },
  created_at: ~U[2024-01-15 10:30:00Z],
  updated_at: ~U[2024-01-15 10:35:00Z],
  message_count: 3
}
```

## Best Practices

1. **Clean up conversations**: Delete when no longer needed to free memory
2. **Use system prompts**: Set conversation context at creation
3. **Track message count**: Monitor for context window limits
4. **Handle errors**: Always handle `:conversation_not_found`
5. **Format for LLM**: Use `get_messages_for_llm/1` for API calls

## Limitations

- **No persistence**: Conversations are lost on application restart
- **Memory-based**: Large conversations consume memory
- **Single node**: ETS is local to the node (no clustering)

For persistent conversations across restarts, consider storing conversation state in a database and loading it back into the Manager when needed.
