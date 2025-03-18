# Jido AI Agent and Skill Integration Guide

## Introduction

The Jido AI framework extends the core Jido Agent SDK with powerful artificial intelligence capabilities. Rather than being a standalone system, Jido AI builds upon the foundation of the Jido Agent architecture, adding specialized modules for AI model integration, prompt management, and intelligent conversation handling.

This guide explores how to leverage the AI-specific extensions (`Jido.AI.Agent` and `Jido.AI.Skill`) within the broader Jido ecosystem to create intelligent, conversational agents that maintain the structured architecture and signal-based communication patterns of the core Jido framework.

## Architectural Overview

### Jido Core Architecture

The Jido framework is built around several key concepts:

- **Agents**: Autonomous entities that process signals and coordinate actions
- **Skills**: Modular capabilities that can be attached to agents
- **Signals**: Structured messages passed between components
- **Actions**: Discrete operations with defined inputs and outputs
- **Instructions**: Routing directives that map signals to actions

### Jido AI Extension

Jido AI extends this foundation with specialized components:

- **AI Agent**: Extends the base `Jido.Agent` with AI capabilities
- **AI Skill**: A specialized skill for processing AI-related signals
- **AI Actions**: Pre-built actions for interacting with AI providers
- **AI Model**: Configuration for connecting to AI providers
- **AI Prompt**: Structured templates for AI interactions

This architecture maintains the clean separation of concerns from the core Jido framework while adding robust AI capabilities.

## Getting Started with Jido.AI.Agent

### Understanding the Extension Pattern

The `Jido.AI.Agent` module is not a standalone agent but rather extends the core `Jido.Agent` module with AI-specific functionality:

```elixir
defmodule Jido.AI.Agent do
  use Jido.Agent,
    name: "jido_ai_agent",
    description: "General purpose AI agent powered by Jido",
    category: "AI Agents",
    tags: ["AI", "Agent"],
    vsn: "0.1.0"
    
  # AI-specific implementation details...
end
```

This means that all core Jido Agent capabilities are available, with additional AI methods provided as extensions.

### Basic Configuration

Creating a Jido AI Agent requires minimal configuration, following the standard Jido Agent initialization pattern with additional AI-specific options:

```elixir
defmodule MyApp.SimpleAgent do
  alias Jido.AI.Agent
  
  def start do
    {:ok, pid} = Agent.start_link(
      # Standard Jido Agent options
      log_level: :debug,
      
      # AI-specific configuration
      ai: [
        model: {:anthropic, model: "claude-3-haiku-20240307"},
        prompt: "You are a helpful assistant. Please answer the following question:\n<%= @message %>"
      ]
    )
    
    {:ok, pid}
  end
  
  def ask(pid, question) do
    Agent.chat_response(pid, question)
  end
end
```

### Key Configuration Options

| Option | Description | Example |
|--------|-------------|---------|
| `model` | Specifies the AI model to use | `{:anthropic, model: "claude-3-haiku-20240307"}` |
| `prompt` | Template for system instructions | `"You are a helpful assistant. Answer: <%= @message %>"` |
| `tools` | List of Jido Actions the agent can use | `[Jido.Actions.Weather, Jido.Actions.Search]` |
| `chat_action` | The Jido Action to handle chat responses | `Jido.AI.Actions.Instructor.ChatResponse` |
| `tool_action` | The Jido Action to handle tool-based responses | `Jido.AI.Actions.Langchain.ToolResponse` |

## Understanding Jido.AI.Skill

The `Jido.AI.Skill` module is a specialized Jido Skill implementation that handles AI-specific signal patterns:

```elixir
defmodule Jido.AI.Skill do
  use Jido.Skill,
    name: "jido_ai_skill",
    description: "General purpose AI skill powered by Jido",
    vsn: "0.1.0",
    opts_key: @ai_opts_key,
    opts_schema: @ai_opts_schema,
    signal_patterns: [
      "jido.ai.**"
    ]
    
  # Implementation details...
end
```

This skill acts as a bridge between the standard Jido signal routing system and AI-specific functionality, handling signal patterns like `jido.ai.chat.response` and transforming them into appropriate AI actions.

### Signal Handling Flow

When a signal is received by a Jido AI Agent:

1. The signal is routed through the agent's skill pipeline
2. If the signal matches a pattern like `jido.ai.**`, the `Jido.AI.Skill` processes it
3. The skill transforms the signal into an appropriate AI action
4. The action communicates with the AI provider and returns the result
5. The result is transformed and returned through the agent's pipeline

This maintains the consistent signal-based architecture of the Jido framework while enabling AI-specific functionality.

## Advanced Agent Patterns

### Dynamic Prompt Engineering

Leverage EEx templates within the Jido templating system for dynamic prompt generation:

```elixir
prompt = """
You are a <%= @persona %> expert with knowledge of <%= @domain %>.
Answer the following question about <%= @topic %>:

<%= @message %>
"""

{:ok, pid} = Agent.start_link(
  ai: [
    model: {:anthropic, model: "claude-3-sonnet-20240229"},
    prompt: prompt
  ]
)

# When asking a question, provide context parameters
Agent.chat_response(pid, "How does it work?", 
  params: %{
    persona: "software engineering",
    domain: "distributed systems",
    topic: "message brokers"
  }
)
```

### Tool Integration with Jido Actions

Enable agents to perform actions using the standard Jido Action system:

```elixir
{:ok, pid} = Agent.start_link(
  ai: [
    model: {:anthropic, model: "claude-3-opus-20240229"},
    prompt: "You are an agent that can look up weather information.",
    tools: [Jido.Actions.Weather.GetForecast, Jido.Actions.Weather.GetCurrentConditions]
  ]
)

# The agent will automatically use tools when necessary
Agent.tool_response(pid, "What's the weather like in New York today?")
```

The key distinction here is that tools in the Jido AI context are standard Jido Actions, maintaining consistency with the core framework.

## Implementing Custom AI Skills

While the `Jido.AI.Skill` provides general purpose AI functionality, you can create custom AI-focused skills that follow the standard Jido Skill pattern:

```elixir
defmodule MyApp.CustomAISkill do
  use Jido.Skill,
    name: "custom_ai_skill",
    description: "Domain-specific AI capabilities",
    signal_patterns: [
      "myapp.ai.**"
    ]
    
  def router(_opts) do
    [
      {"myapp.ai.specialized_response",
       %Instruction{
         action: MyApp.Actions.SpecializedAIResponse,
         params: %{}
       }}
    ]
  end
  
  def handle_signal(signal, _skill_opts) do
    # Process incoming signal before routing
    enhanced_signal = add_domain_context(signal)
    {:ok, enhanced_signal}
  end
  
  def transform_result(_signal, result, _skill_opts) do
    # Process result after action execution
    formatted_result = format_for_domain(result)
    {:ok, formatted_result}
  end
  
  # Helper functions
  defp add_domain_context(signal) do
    # Add domain-specific context to the signal
    Map.update(signal, :data, %{}, fn data ->
      Map.put(data, :domain_context, "Specialized information")
    end)
  end
  
  defp format_for_domain(result) do
    # Format the result for the specific domain
    Map.put(result, :domain_formatted, true)
  end
end
```

## Practical Example: News Reporter Agent

This example demonstrates how to create a complete Jido AI Agent with personality:

```elixir
defmodule Examples.NewsReporterAgent do
  alias Jido.AI.Agent
  require Logger
  
  def start do
    {:ok, pid} = Agent.start_link(
      # Standard Jido Agent options
      log_level: :debug,
      
      # AI-specific configuration
      ai: [
        model: {:anthropic, model: "claude-3-haiku-20240307"},
        prompt: """
        You are an enthusiastic news reporter with a flair for storytelling! 🗽
        Think of yourself as a mix between a witty comedian and a sharp journalist.
        Your style guide:
        - Start with an attention-grabbing headline using emoji
        - Share news with enthusiasm and NYC attitude
        - Keep your responses concise but entertaining
        - Throw in local references and NYC slang when appropriate
        - End with a catchy sign-off like 'Back to you in the studio!' or 'Reporting live from the Big Apple!'
        
        Answer this question:
        <%= @message %>
        """
      ]
    )
    
    {:ok, pid}
  end
  
  def report_news(pid, topic) do
    # Uses the Jido.AI.Agent extension method
    {:ok, response} = Agent.chat_response(pid, topic)
    Logger.info("News report: #{response.response}")
    response.response
  end
end
```

## Jido.AI Actions

The Jido AI framework provides several specialized Jido Actions for AI operations:

### Instructor-based Actions

- `Jido.AI.Actions.Instructor.ChatResponse`: General purpose chat response
- `Jido.AI.Actions.Instructor.BooleanResponse`: Yes/no answers with explanation
- `Jido.AI.Actions.Instructor.ChoiceResponse`: Selection from options

### LangChain-based Actions

- `Jido.AI.Actions.Langchain.ToolResponse`: Tool-augmented responses

### OpenAI/Ex-based Actions

- `Jido.AI.Actions.OpenaiEx.Embeddings`: Vector embedding generation
- `Jido.AI.Actions.OpenaiEx.ImageGeneration`: Image creation

These actions follow the standard Jido Action pattern, maintaining consistency with the core framework.

## Advanced Response Handling

### Boolean Responses

For yes/no questions with explanation:

```elixir
{:ok, result} = Agent.boolean_response(pid, "Is Paris the capital of France?")
# Returns:
# %{
#   result: true,
#   explanation: "Yes, Paris is the capital of France...",
#   confidence: 0.99,
#   is_ambiguous: false
# }
```

### Tool Responses

For actions requiring tool use, leveraging the standard Jido Action system:

```elixir
{:ok, result} = Agent.tool_response(pid, "What's the weather in Tokyo?")
# Returns:
# %{
#   result: "The current weather in Tokyo is...",
#   tool_results: [
#     %{tool: "weather_lookup", result: %{temperature: 22, conditions: "Sunny"}}
#   ]
# }
```

## Working with Jido.AI.Provider

The framework offers configurable provider adapters that integrate with the Jido environment:

```elixir
# Define a model explicitly
{:ok, model} = Jido.AI.Model.from({:anthropic, 
  model: "claude-3-haiku-20240307",
  api_key: System.get_env("ANTHROPIC_API_KEY")
})

# Use the model with an agent
{:ok, pid} = Agent.start_link(ai: [model: model])
```

The provider system allows for consistent configuration and access to various AI providers while maintaining the Jido architectural patterns.

## Best Practices

### Integration with Existing Jido Agents

When adding AI capabilities to an existing Jido Agent:

```elixir
defmodule MyApp.EnhancedAgent do
  def start do
    {:ok, pid} = Jido.Agent.start_link(
      name: "enhanced_agent",
      skills: [
        MyApp.ExistingSkill,
        MyApp.AnotherSkill,
        Jido.AI.Skill  # Add the AI skill to the existing agent
      ],
      
      # Add AI-specific configuration
      ai: [
        model: {:anthropic, model: "claude-3-haiku-20240307"},
        prompt: "You are a helpful assistant integrated into the enhanced agent."
      ]
    )
    
    {:ok, pid}
  end
end
```

### Combining Multiple AI and Non-AI Skills

Leverage the full power of the Jido framework by combining AI and non-AI skills:

```elixir
{:ok, pid} = Jido.AI.Agent.start_link(
  skills: [
    # Standard Jido skills
    MyApp.DatabaseSkill,
    MyApp.NotificationSkill,
    
    # AI-specific skills
    Jido.AI.Skill,
    MyApp.CustomAISkill
  ],
  
  ai: [
    model: {:anthropic, model: "claude-3-haiku-20240307"},
    prompt: "You are a helpful assistant with database and notification capabilities."
  ]
)
```

### Error Handling

Implement robust error management following Jido patterns:

```elixir
def ask_question(pid, question) do
  case Agent.chat_response(pid, question) do
    {:ok, response} -> 
      {:ok, response.response}
    {:error, reason} -> 
      Logger.error("AI request failed: #{inspect(reason)}")
      {:error, "Unable to process your request at this time"}
  end
end
```

## Conclusion

The Jido AI Agent and Skill modules provide a powerful extension to the core Jido framework, adding robust AI capabilities while maintaining the structured architecture, signal-based communication, and separation of concerns that make Jido effective for building complex agent systems.

By understanding how the AI components integrate with and extend the core Jido functionality, developers can create sophisticated AI-powered experiences that leverage the full power of the Jido ecosystem.

## Further Resources

- [Jido GitHub Repository](https://github.com/agentjido/jido)
- [Jido Framework Documentation](https://hexdocs.pm/jido)