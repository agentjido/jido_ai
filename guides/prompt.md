# Jido.AI.Prompt Module Documentation

## Overview

The `Jido.AI.Prompt` module provides a powerful, struct-based approach to managing AI conversations. It enables developers to create, version, and render prompts with dynamic content substitution, making it ideal for building sophisticated AI interactions in Elixir applications.

## Core Concepts

### What Problem Does Jido.AI.Prompt Solve?

When building AI-powered applications, managing prompts as simple strings becomes unwieldy as applications grow in complexity. The `Jido.AI.Prompt` module solves this by offering:

1. **Structured Prompt Management**: Organizes prompts as versioned, inspectable structs
2. **Template Support**: Integrates seamlessly with EEx and Liquid templates
3. **Conversation History**: Maintains version history for debugging and rollback
4. **Parameter Substitution**: Simplifies dynamic content generation

## Basic Usage

### Creating a Simple Prompt

```elixir
alias Jido.AI.Prompt

# Create a basic prompt with a single message
prompt = Prompt.new(%{
  messages: [
    %{role: :user, content: "Hello AI assistant"}
  ]
})

# Create a prompt with specific role and content
system_prompt = Prompt.new(:system, "You are a helpful coding assistant specializing in Elixir")
```

### Working with Templates

```elixir
# Create a prompt with EEx template
template_prompt = Prompt.new(%{
  messages: [
    %{role: :system, content: "You are a <%= @assistant_type %>", engine: :eex},
    %{role: :user, content: "Help me with <%= @topic %>", engine: :eex}
  ],
  params: %{
    assistant_type: "helpful AI assistant",
    topic: "prompt engineering"
  }
})

# Render messages with default parameters
messages = Prompt.render(template_prompt)
# => [
#      %{role: :system, content: "You are a helpful AI assistant"},
#      %{role: :user, content: "Help me with prompt engineering"}
#    ]

# Override parameters during rendering
messages = Prompt.render(template_prompt, %{topic: "Elixir programming"})
# => [
#      %{role: :system, content: "You are a helpful AI assistant"},
#      %{role: :user, content: "Help me with Elixir programming"}
#    ]
```

## Going Deeper

### Prompt Versioning

The `Prompt` module maintains version history, enabling you to track changes and roll back when needed:

```elixir
# Create initial prompt
prompt = Prompt.new(:user, "Initial question")

# Create a new version with additional message
v2 = Prompt.new_version(prompt, fn p -> 
  Prompt.add_message(p, :assistant, "How can I help you?") 
end)

# Add another message in version 3
v3 = Prompt.new_version(v2, fn p -> 
  Prompt.add_message(p, :user, "Tell me about Elixir") 
end)

# List all versions
versions = Prompt.list_versions(v3)  # [3, 2, 1]

# Retrieve a specific version
{:ok, original} = Prompt.get_version(v3, 1)
```

### Template Engines

Jido.AI.Prompt supports multiple template engines:

```elixir
# Using EEx templates
eex_prompt = Prompt.new(%{
  messages: [
    %{role: :user, content: "My name is <%= @name %>, I am <%= @age %> years old", engine: :eex}
  ],
  params: %{name: "Alice", age: 30}
})

# Using Liquid templates
liquid_prompt = Prompt.new(%{
  messages: [
    %{role: :user, content: "My name is {{ name }}, I am {{ age }} years old", engine: :liquid}
  ],
  params: %{name: "Bob", age: 25}
})
```

### Converting to Text

For debugging or when an API requires a single text string:

```elixir
text_prompt = Prompt.to_text(prompt)
# => "[system] You are an assistant\n[user] Hello"
```

## Advanced Patterns

### Composing Multi-part Conversations

Build complex conversation flows while maintaining context:

```elixir
# Start with a system message
prompt = Prompt.new(:system, "You are an Elixir programming assistant")

# Add user question
prompt = Prompt.add_message(prompt, :user, "How do I use GenServer?")

# Add assistant response
prompt = Prompt.add_message(prompt, :assistant, "GenServer is a behavior module for implementing...")

# Add follow-up user question
prompt = Prompt.add_message(prompt, :user, "Can you show me an example?")

# Render the entire conversation
conversation = Prompt.render(prompt)
```

### Using Template Parameters

Templates become powerful when combined with dynamic parameters:

```elixir
# Create a reusable prompt template with placeholders
code_review_prompt = Prompt.new(%{
  messages: [
    %{role: :system, content: "You are a code reviewer focusing on <%= @language %>", engine: :eex},
    %{role: :user, content: "Please review this code:\n\n```<%= @language %>\n<%= @code %>\n```", engine: :eex}
  ],
  params: %{
    language: "elixir",
    code: ""  # Will be provided later
  }
})

# Use it with specific code
elixir_review = Prompt.render(code_review_prompt, %{
  code: """
  defmodule Calculator do
    def add(a, b), do: a + b
  end
  """
})

# Reuse with different language and code
js_review = Prompt.render(code_review_prompt, %{
  language: "javascript",
  code: """
  function add(a, b) {
    return a + b;
  }
  """
})
```

### Error Handling

Robust error handling ensures your application gracefully manages template rendering failures:

```elixir
case Prompt.validate_prompt_opts(user_input) do
  {:ok, prompt} ->
    try do
      rendered = Prompt.render(prompt)
      # Use rendered messages
    rescue
      e in Jido.AI.Error ->
        # Handle template rendering errors
        Logger.error("Failed to render prompt: #{Exception.message(e)}")
        # Fallback behavior
    end
  
  {:error, reason} ->
    # Handle invalid prompt configuration
    Logger.error("Invalid prompt: #{reason}")
end
```

## Common Questions

### How do I create a prompt with multiple messages?

```elixir
Prompt.new(%{
  messages: [
    %{role: :system, content: "You are a helpful assistant"},
    %{role: :user, content: "Hello!"},
    %{role: :assistant, content: "Hi there! How can I help you today?"}
  ]
})
```

### How can I add messages to an existing prompt?

```elixir
prompt = Prompt.new(:user, "Initial message")
updated = Prompt.add_message(prompt, :assistant, "Response message")
```

### Can I use more complex logic in templates?

Yes, you can use full EEx syntax for complex logic:

```elixir
template = """
<%= if @advanced_mode do %>
  Detailed technical response with advanced terminology:
  <%= @technical_content %>
<% else %>
  Simplified explanation for beginners:
  <%= @simple_content %>
<% end %>
"""

prompt = Prompt.new(%{
  messages: [
    %{role: :assistant, content: template, engine: :eex}
  ],
  params: %{
    advanced_mode: false,
    technical_content: "...",
    simple_content: "..."
  }
})
```

## Best Practices

1. **Separate Structure from Content**: Use templates to keep prompt structure separate from variable content
2. **Version Critical Prompts**: Leverage versioning for important prompt chains
3. **Use Descriptive Parameter Names**: Make templates readable with clear variable names
4. **Validate Inputs**: Sanitize user inputs before including them in templates
5. **Keep a Library of Reusable Prompts**: Build and share common prompt patterns

## Integration with Jido.AI Ecosystem

The `Prompt` module integrates seamlessly with other Jido.AI components:

```elixir
alias Jido.AI.Prompt
alias Jido.AI.Prompt.Template
import Jido.AI.Prompt.Sigil

# Create a system prompt template using sigil
system_template = ~AI"You are an <%= @assistant_type %> specialized in <%= @domain %>"

# Create a user prompt
user_prompt = Prompt.new(:user, "Help me with <%= @problem %>", engine: :eex)

# Combine into a complete prompt
full_prompt = Prompt.new(%{
  messages: [
    Template.to_message!(system_template, %{assistant_type: "AI assistant", domain: "Elixir"}),
    # Add more messages
  ]
})
```

By mastering the `Jido.AI.Prompt` module, you can build sophisticated AI interactions with clean, maintainable code that scales with your application's complexity.