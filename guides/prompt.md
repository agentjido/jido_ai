# Jido.AI.Prompt

## Introduction

The `Jido.AI.Prompt` module provides a structured approach to managing conversations with Large Language Models (LLMs). Instead of working with simple strings, this module enables developers to create, version, manipulate, and render sophisticated prompts with dynamic content substitution.

## Core Concepts

### Understanding the Prompt Architecture

The `Jido.AI.Prompt` module is built around a central struct with these key components:

```elixir
typedstruct do
  field(:id, String.t(), default: Jido.Util.generate_id())
  field(:version, non_neg_integer(), default: 1)
  field(:history, list(map()), default: [])
  field(:messages, list(MessageItem.t()), default: [])
  field(:params, map(), default: %{})
  field(:metadata, map(), default: %{})
end
```

- **Messages**: The core content of the prompt, each with a role (system, user, assistant)
- **Parameters**: Values that can be interpolated into templated messages
- **Versioning**: Built-in tracking of prompt changes with history and rollback capability

## Getting Started

### Creating Basic Prompts

```elixir
alias Jido.AI.Prompt

# Simple prompt with a single message
prompt = Prompt.new(:user, "How do I use Elixir's pattern matching?")

# Multiple messages
complex_prompt = Prompt.new(%{
  messages: [
    %{role: :system, content: "You are a programming assistant"},
    %{role: :user, content: "Explain pattern matching in Elixir"}
  ]
})
```

### Rendering Prompts for LLM Submission

To convert your prompt into a format suitable for LLM API calls:

```elixir
# Get a list of message maps
messages = Prompt.render(prompt)
# => [%{role: :user, content: "How do I use Elixir's pattern matching?"}]

# For debugging or text-based APIs
text_format = Prompt.to_text(prompt)
# => "[user] How do I use Elixir's pattern matching?"
```

## Working with Templates

The module's true power emerges when using templates for dynamic content generation.

### Template-Based Messages

```elixir
# Create a prompt with EEx templates
template_prompt = Prompt.new(%{
  messages: [
    %{role: :system, content: "You are a <%= @assistant_type %>", engine: :eex},
    %{role: :user, content: "Help me with <%= @topic %>", engine: :eex}
  ],
  params: %{
    assistant_type: "programming assistant",
    topic: "recursion"
  }
})

# Render with default parameters
messages = Prompt.render(template_prompt)

# Override parameters during rendering
messages = Prompt.render(template_prompt, %{topic: "list comprehensions"})
```

### Template Engines

The module supports different template engines:

```elixir
# EEx (Embedded Elixir) - default
eex_message = %{
  role: :user, 
  content: "My name is <%= @name %>, I need help with <%= @topic %>", 
  engine: :eex
}

# Liquid templates
liquid_message = %{
  role: :user, 
  content: "My name is {{ name }}, I need help with {{ topic }}", 
  engine: :liquid
}
```

## Building Conversations

### Adding Messages

```elixir
# Start with a system message
prompt = Prompt.new(:system, "You are a helpful assistant")

# Add a user question
prompt = Prompt.add_message(prompt, :user, "How does pattern matching work?")

# Add an assistant response
prompt = Prompt.add_message(prompt, :assistant, "Pattern matching in Elixir allows...")

# Add a follow-up question
prompt = Prompt.add_message(prompt, :user, "Can you show an example?")
```

### Message Roles and Validation

The module enforces rules about message roles:

1. Only one system message is allowed
2. If present, the system message must be the first message

```elixir
# This works - system message first
valid_prompt = Prompt.new(%{
  messages: [
    %{role: :system, content: "You are an assistant"},
    %{role: :user, content: "Hello"}
  ]
})

# This raises an error - system message not first
# invalid_prompt = Prompt.new(%{
#   messages: [
#     %{role: :user, content: "Hello"},
#     %{role: :system, content: "You are an assistant"}
#   ]
# })
```

## Versioning and History

### Creating New Versions

```elixir
# Start with a basic prompt
prompt = Prompt.new(:user, "Initial question")

# Create version 2 with an additional message
v2 = Prompt.new_version(prompt, fn p -> 
  Prompt.add_message(p, :assistant, "Initial response") 
end)

# Create version 3
v3 = Prompt.new_version(v2, fn p ->
  Prompt.add_message(p, :user, "Follow-up question")
end)
```

### Managing Versions

```elixir
# List all versions
versions = Prompt.list_versions(v3)  # [3, 2, 1]

# Retrieve a specific version
{:ok, original} = Prompt.get_version(v3, 1)

# Compare versions
{:ok, diff} = Prompt.compare_versions(v3, 3, 1)
# => %{added_messages: [...], removed_messages: [...]}
```

## Advanced Usage Patterns

### Parameter Substitution with Logic

```elixir
template = """
<%= if @advanced_mode do %>
You are an expert-level <%= @domain %> consultant. Use technical terminology and provide in-depth explanations.
<% else %>
You are a helpful <%= @domain %> assistant. Explain concepts simply and avoid technical jargon.
<% end %>
"""

prompt = Prompt.new(%{
  messages: [
    %{role: :system, content: template, engine: :eex}
  ],
  params: %{
    advanced_mode: false,
    domain: "machine learning"
  }
})
```

### Creating Reusable Templates

For common prompt patterns, leverage the `Template` module:

```elixir
alias Jido.AI.Prompt.Template

# Use template to create prompts
prompt = Prompt.new(%{
  messages: [
    %{role: :system, content: "You are a code reviewer"},
    %{role: :user, content: Template.format(code_review_template, %{
      language: "elixir",
      code: "defmodule Math do\n  def add(a, b), do: a + b\nend",
      focus_areas: ["Performance", "Readability", "Error handling"]
    }), engine: :none}
  ]
})
```

## Integration with AI Actions

Jido.AI includes action modules that use these prompts for LLM interactions:

```elixir
# Create a prompt
prompt = Prompt.new(:user, "What is the Elixir programming language?")

# Use with ChatResponse action
{:ok, result} = Jido.AI.Actions.Instructor.ChatResponse.run(%{
  model: %Jido.AI.Model{provider: :anthropic, model: "claude-3-haiku-20240307"},
  prompt: prompt,
  temperature: 0.7
}, %{})

# Response is in result.response
IO.puts(result.response)
```

## Error Handling and Validation

### Validating Prompt Options

```elixir
case Prompt.validate_prompt_opts(user_input) do
  {:ok, validated_prompt} ->
    # Use the validated prompt
    messages = Prompt.render(validated_prompt)
    # Call LLM with messages
    
  {:error, reason} ->
    # Handle validation error
    Logger.error("Invalid prompt: #{reason}")
end
```

### Template Rendering Errors

Handle potential rendering errors when working with templates:

```elixir
try do
  messages = Prompt.render(template_prompt)
  # Use rendered messages
rescue
  e in Jido.AI.Error ->
    # Handle template rendering errors
    Logger.error("Failed to render prompt: #{Exception.message(e)}")
end
```

## Best Practices

1. **Separate Structure from Content**
   - Use templates to isolate prompt structure from variable content
   - Create reusable prompt patterns for common use cases

2. **Leverage Role-Based Messaging**
   - Use system messages for overall instruction
   - Use user messages for specific queries
   - Use assistant messages to provide context from previous responses

3. **Manage Complexity with Versioning**
   - Use the built-in versioning for complex, evolving prompts
   - Compare versions when debugging unexpected LLM behaviors

4. **Validate and Sanitize Inputs**
   - Use `sanitize_inputs` to prevent template injection when working with user inputs
   - Validate inputs before rendering templates

5. **Progressive Enhancement**
   - Start with simple prompts and gradually add complexity
   - Test prompt variations to optimize LLM responses

## Example Workflow: Implementing a Chain-of-Thought

```elixir
defmodule ChainOfThoughtPrompt do
  alias Jido.AI.Prompt
  alias Jido.AI.Model
  alias Jido.AI.Actions.Instructor.ChatResponse
  
  def solve_problem(problem_statement) do
    # Create a base prompt with system instruction
    prompt = Prompt.new(:system, """
    You are a problem-solving assistant that uses step-by-step reasoning.
    Always break down problems into clear steps before providing the final answer.
    """)
    
    # Add the user's problem
    prompt = Prompt.add_message(prompt, :user, problem_statement)
    
    # Get initial response with reasoning
    {:ok, init_result} = ChatResponse.run(%{
      model: %Model{provider: :anthropic, model: "claude-3-haiku-20240307"},
      prompt: prompt
    }, %{})
    
    # Add the response to the conversation
    prompt = Prompt.add_message(prompt, :assistant, init_result.response)
    
    # Add a follow-up to verify the solution
    prompt = Prompt.add_message(prompt, :user, """
    Thank you for the step-by-step solution. 
    Can you check your work and ensure the final answer is correct?
    """)
    
    # Get verification response
    {:ok, final_result} = ChatResponse.run(%{
      model: %Model{provider: :anthropic, model: "claude-3-haiku-20240307"},
      prompt: prompt
    }, %{})
    
    # Return the complete conversation and final response
    %{
      conversation: Prompt.to_text(prompt),
      final_answer: final_result.response
    }
  end
end
```

## Conclusion

The `Jido.AI.Prompt` module provides a powerful foundation for building sophisticated LLM interactions in Elixir. By leveraging its structured approach to prompt management, templates, and version control, developers can create robust, maintainable, and dynamic LLM-powered applications.

By mastering these techniques, you'll be able to create prompt systems that adapt to changing requirements, maintain context across complex conversations, and deliver consistent, high-quality interactions with large language models.