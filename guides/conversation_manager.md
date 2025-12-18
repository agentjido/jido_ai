# Conversation Manager: Stateful Multi-Turn Tool-Enabled Conversations

## Introduction

The **ConversationManager** system provides stateful management for multi-turn conversations with Large Language Models (LLMs) that use tools and function calling. It consists of three coordinated components that handle conversation state, tool integration, and response processing.

### Why Conversation Manager?

Tool-enabled LLM interactions require careful state management across multiple conversation turns. The ConversationManager system addresses this by:

- **Maintaining Context**: Preserves message history across multiple turns
- **Managing Tools**: Configures and tracks available tools per conversation
- **Coordinating Execution**: Orchestrates tool calls with LLM responses
- **Ensuring Reliability**: Handles errors gracefully without losing conversation state
- **Enabling Scalability**: Supports multiple concurrent conversations with isolated state

### Architecture Overview

The system consists of three main components:

```
┌─────────────────────────────────────────────────────────────┐
│                    ToolIntegrationManager                    │
│                    (High-Level Interface)                    │
│  • Start/continue conversations                             │
│  • Coordinate tool execution flow                           │
│  • Manage conversation lifecycle                            │
└──────────────────┬────────────────────┬─────────────────────┘
                   │                    │
                   v                    v
    ┌──────────────────────┐  ┌──────────────────────┐
    │ ConversationManager  │  │ ToolResponseHandler  │
    │   (State Storage)    │  │  (Response Processing)│
    │ • Message history    │  │ • Extract tool calls │
    │ • Tool configs       │  │ • Execute tools      │
    │ • Options storage    │  │ • Format results     │
    │ • Cleanup            │  │ • Error handling     │
    └──────────────────────┘  └──────────────────────┘
```

### Performance Characteristics

| Aspect | Details |
|--------|---------|
| **Storage** | In-memory ETS tables for fast access |
| **Concurrency** | Thread-safe, supports multiple conversations |
| **Cleanup** | Automatic expiration after 24 hours |
| **Tool Execution** | Parallel execution with configurable timeout |
| **Max Concurrency** | 4 tools execute simultaneously |
| **Default Timeout** | 30 seconds per tool |

> **💡 Practical Examples**: See the [Conversation Manager examples directory](../examples/conversation-manager/) for complete working implementations including a basic chat and a multi-tool agent.

---

## Core Components

### 1. ConversationManager

**Purpose**: Manages conversation state storage and retrieval.

**Responsibilities**:
- Create and track conversations with unique IDs
- Store message history (user, assistant, tool messages)
- Persist tool configurations per conversation
- Store conversation-specific options
- Track metadata (timestamps, message counts)
- Automatic cleanup of expired conversations

**Key Functions**:

```elixir
# Lifecycle
{:ok, conv_id} = ConversationManager.create_conversation()
:ok = ConversationManager.end_conversation(conv_id)

# Tool Configuration
:ok = ConversationManager.set_tools(conv_id, tool_descriptors)
{:ok, tools} = ConversationManager.get_tools(conv_id)
{:ok, tool} = ConversationManager.find_tool_by_name(conv_id, "weather")

# Options Management
:ok = ConversationManager.set_options(conv_id, %{model: "gpt-4", temperature: 0.7})
{:ok, options} = ConversationManager.get_options(conv_id)

# Message History
:ok = ConversationManager.add_user_message(conv_id, "Hello!")
:ok = ConversationManager.add_assistant_response(conv_id, response)
:ok = ConversationManager.add_tool_results(conv_id, tool_results)
{:ok, history} = ConversationManager.get_history(conv_id)

# Metadata
{:ok, metadata} = ConversationManager.get_conversation_metadata(conv_id)
```

**Storage Structure**:

Each conversation is stored as:

```elixir
%{
  id: "conversation_id",
  created_at: ~U[2024-01-01 10:00:00Z],
  last_activity: ~U[2024-01-01 10:05:00Z],
  messages: [
    %{role: "user", content: "Hello", timestamp: ~U[...], metadata: %{}},
    %{role: "assistant", content: "Hi!", timestamp: ~U[...], metadata: %{}}
  ],
  tools: [
    %{name: "weather", action_module: WeatherAction, ...}
  ],
  options: %{model: "gpt-4", temperature: 0.7},
  metadata: %{message_count: 2, total_tokens: 50}
}
```

### 2. ToolIntegrationManager

**Purpose**: High-level interface for tool-enabled LLM interactions.

**Responsibilities**:
- Provide simple API for tool-enabled requests
- Coordinate ConversationManager and ToolResponseHandler
- Handle conversation lifecycle
- Manage request options and validation
- Support both streaming and non-streaming responses

**Key Functions**:

```elixir
# One-off tool-enabled request
{:ok, response} = ToolIntegrationManager.generate_with_tools(
  "What's the weather in Paris?",
  [WeatherAction, CalculatorAction],
  %{model: "gpt-4", temperature: 0.7}
)

# Multi-turn conversation
{:ok, conv_id} = ToolIntegrationManager.start_conversation(
  [WeatherAction],
  %{model: "gpt-4"}
)

{:ok, response} = ToolIntegrationManager.continue_conversation(
  conv_id,
  "What's the weather in Paris?"
)

{:ok, response} = ToolIntegrationManager.continue_conversation(
  conv_id,
  "And in London?"
)

# Get conversation history
{:ok, history} = ToolIntegrationManager.get_conversation_history(conv_id)

# End conversation
:ok = ToolIntegrationManager.end_conversation(conv_id)
```

**Options**:

```elixir
%{
  # LLM Configuration
  model: "gpt-4",              # Model to use
  temperature: 0.7,            # Creativity (0.0-2.0)
  max_tokens: 1000,            # Maximum response length

  # Tool Configuration
  tool_choice: :auto,          # :auto | :none | :required | {:function, name}
  max_tool_calls: 5,           # Max tools per response

  # Execution Settings
  stream: false,               # Enable streaming
  timeout: 30_000,             # Tool execution timeout (ms)

  # Context
  context: %{},                # Additional context for tool execution
  conversation_id: "..."       # Optional: resume existing conversation
}
```

### 3. ToolResponseHandler

**Purpose**: Processes LLM responses and executes tool calls.

**Responsibilities**:
- Extract tool calls from LLM responses
- Execute tools with proper error handling
- Aggregate tool execution results
- Handle streaming responses with incremental tool calls
- Format final responses with tool results

**Key Functions**:

```elixir
# Process non-streaming response
{:ok, processed_response} = ToolResponseHandler.process_llm_response(
  llm_response,
  conversation_id,
  %{max_tool_calls: 5, timeout: 30_000}
)

# Process streaming response
{:ok, processed_response} = ToolResponseHandler.process_streaming_response(
  response_stream,
  conversation_id,
  %{timeout: 60_000}
)

# Execute tool calls directly
tool_calls = [
  %{
    id: "call_1",
    function: %{name: "weather", arguments: %{"location" => "Paris"}}
  }
]

{:ok, results} = ToolResponseHandler.execute_tool_calls(tool_calls, context)
```

**Tool Execution Features**:

- **Parallel Execution**: Up to 4 tools execute concurrently
- **Timeout Protection**: Configurable per-tool timeout (default 30s)
- **Error Isolation**: Individual tool failures don't stop other tools
- **Graceful Degradation**: Partial results returned if some tools fail
- **Circuit Breaker**: Prevents cascade failures

---

## Complete Request Flow

Understanding how the three components work together:

```
1. User Initiates Request
   ↓
2. ToolIntegrationManager.generate_with_tools()
   • Creates conversation via ConversationManager
   • Validates options
   • Converts Jido Actions to tool descriptors
   • Stores tools in conversation
   ↓
3. Makes LLM Request (via ReqLLM)
   • Sends message + available tools
   • LLM returns response (may include tool calls)
   ↓
4. ToolResponseHandler.process_llm_response()
   • Extracts tool calls from response
   • For each tool call:
     - Looks up tool via ConversationManager.find_tool_by_name()
     - Executes tool (parallel, with timeout)
     - Formats result
   • Aggregates all tool results
   ↓
5. Return Final Response
   • Response includes:
     - Original LLM content
     - Tool execution results
     - Metadata (usage, timing)
   ↓
6. ConversationManager Updates State
   • Adds assistant response to history
   • Adds tool results to history
   • Updates last_activity timestamp
```

---

## Usage Patterns

### Pattern 1: One-Off Tool Request

For single requests without maintaining conversation state:

```elixir
defmodule MyApp.SimpleToolUser do
  alias Jido.AI.ReqLlmBridge.ToolIntegrationManager

  def ask_with_tools(question, tools) do
    case ToolIntegrationManager.generate_with_tools(question, tools) do
      {:ok, response} ->
        IO.puts("Answer: #{response.content}")
        {:ok, response}

      {:error, reason} ->
        IO.puts("Error: #{inspect(reason)}")
        {:error, reason}
    end
  end
end

# Usage
MyApp.SimpleToolUser.ask_with_tools(
  "What's 15 * 23?",
  [CalculatorAction]
)
```

### Pattern 2: Multi-Turn Conversation

For maintaining context across multiple exchanges:

```elixir
defmodule MyApp.ConversationalAgent do
  alias Jido.AI.ReqLlmBridge.ToolIntegrationManager

  def start_session(tools, options \\ %{}) do
    case ToolIntegrationManager.start_conversation(tools, options) do
      {:ok, conv_id} ->
        {:ok, %{conversation_id: conv_id, tools: tools}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def chat(session, message) do
    case ToolIntegrationManager.continue_conversation(
      session.conversation_id,
      message
    ) do
      {:ok, response} ->
        {:ok, response}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def end_session(session) do
    ToolIntegrationManager.end_conversation(session.conversation_id)
  end
end

# Usage
{:ok, session} = MyApp.ConversationalAgent.start_session([WeatherAction])

{:ok, response1} = MyApp.ConversationalAgent.chat(
  session,
  "What's the weather in Paris?"
)

{:ok, response2} = MyApp.ConversationalAgent.chat(
  session,
  "And what about tomorrow?"
)

:ok = MyApp.ConversationalAgent.end_session(session)
```

### Pattern 3: Conversation with History Analysis

For examining conversation history and extracting insights:

```elixir
defmodule MyApp.ConversationAnalyzer do
  alias Jido.AI.ReqLlmBridge.ToolIntegrationManager

  def analyze_conversation(conversation_id) do
    with {:ok, history} <- ToolIntegrationManager.get_conversation_history(conversation_id),
         {:ok, metadata} <- get_conversation_metadata(conversation_id) do

      summary = %{
        total_messages: metadata.message_count,
        user_messages: count_by_role(history, "user"),
        assistant_messages: count_by_role(history, "assistant"),
        tool_calls: count_by_role(history, "tool"),
        conversation_duration: calculate_duration(metadata),
        topics: extract_topics(history)
      }

      {:ok, summary}
    end
  end

  defp count_by_role(history, role) do
    Enum.count(history, fn msg -> msg.role == role end)
  end

  defp calculate_duration(metadata) do
    DateTime.diff(metadata.last_activity, metadata.created_at)
  end

  defp extract_topics(history) do
    # Implementation to extract topics from messages
    []
  end
end
```

### Pattern 4: Stateful Agent with Tool Rotation

For agents that can add/remove tools dynamically:

```elixir
defmodule MyApp.DynamicToolAgent do
  alias Jido.AI.ReqLlmBridge.{ConversationManager, ToolIntegrationManager}

  def create_agent(initial_tools, options \\ %{}) do
    {:ok, conv_id} = ToolIntegrationManager.start_conversation(initial_tools, options)

    %{
      conversation_id: conv_id,
      available_tools: initial_tools
    }
  end

  def add_tool(agent, new_tool) do
    updated_tools = [new_tool | agent.available_tools] |> Enum.uniq()

    # Convert tools to descriptors and update conversation
    # (This requires accessing ToolBuilder, typically done internally)

    %{agent | available_tools: updated_tools}
  end

  def remove_tool(agent, tool_to_remove) do
    updated_tools = List.delete(agent.available_tools, tool_to_remove)

    # Update conversation tools

    %{agent | available_tools: updated_tools}
  end

  def process(agent, message) do
    ToolIntegrationManager.continue_conversation(
      agent.conversation_id,
      message
    )
  end
end

# Usage
agent = MyApp.DynamicToolAgent.create_agent([WeatherAction])

# Add calculator when needed
agent = MyApp.DynamicToolAgent.add_tool(agent, CalculatorAction)

{:ok, response} = MyApp.DynamicToolAgent.process(
  agent,
  "What's the weather in Paris? Also calculate 15 * 23."
)
```

### Pattern 5: Error Handling and Recovery

For robust production applications:

```elixir
defmodule MyApp.ResilientAgent do
  alias Jido.AI.ReqLlmBridge.ToolIntegrationManager
  require Logger

  def chat_with_retry(conversation_id, message, retries \\ 3) do
    case ToolIntegrationManager.continue_conversation(conversation_id, message) do
      {:ok, response} ->
        handle_response(response)

      {:error, {:tool_execution_failed, _} = error} ->
        Logger.warning("Tool execution failed: #{inspect(error)}")
        # Continue with LLM response even if tools failed
        {:ok, :partial_success}

      {:error, {:llm_request_failed, reason}} when retries > 0 ->
        Logger.warning("LLM request failed, retrying: #{inspect(reason)}")
        :timer.sleep(1000)
        chat_with_retry(conversation_id, message, retries - 1)

      {:error, reason} ->
        Logger.error("Chat failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp handle_response(response) do
    cond do
      has_tool_errors?(response) ->
        Logger.warning("Some tools failed but response received")
        {:ok, :partial_success, response}

      response.finished ->
        {:ok, :complete, response}

      true ->
        {:ok, :incomplete, response}
    end
  end

  defp has_tool_errors?(response) do
    Map.get(response, :tool_execution_errors, []) != []
  end
end
```

---

## Best Practices

### 1. Conversation Lifecycle Management

**Always clean up conversations:**

```elixir
def with_conversation(tools, options, fun) do
  {:ok, conv_id} = ToolIntegrationManager.start_conversation(tools, options)

  try do
    fun.(conv_id)
  after
    ToolIntegrationManager.end_conversation(conv_id)
  end
end

# Usage
with_conversation([WeatherAction], %{}, fn conv_id ->
  ToolIntegrationManager.continue_conversation(conv_id, "What's the weather?")
end)
```

### 2. Tool Configuration

**Configure tools at conversation start:**

```elixir
# Good: Set tools once at start
{:ok, conv_id} = ToolIntegrationManager.start_conversation(
  [WeatherAction, CalculatorAction, SearchAction],
  %{model: "gpt-4"}
)

# Avoid: Trying to change tools mid-conversation
# (Requires manual ConversationManager manipulation)
```

### 3. Option Defaults

**Provide sensible defaults:**

```elixir
defmodule MyApp.Defaults do
  def conversation_options do
    %{
      model: Application.get_env(:my_app, :default_model, "gpt-4"),
      temperature: 0.7,
      max_tokens: 1500,
      max_tool_calls: 10,
      timeout: 45_000
    }
  end
end

# Usage
options = Map.merge(
  MyApp.Defaults.conversation_options(),
  %{temperature: 0.9}  # Override for this conversation
)

{:ok, conv_id} = ToolIntegrationManager.start_conversation(tools, options)
```

### 4. Error Handling

**Handle errors at appropriate levels:**

```elixir
case ToolIntegrationManager.continue_conversation(conv_id, message) do
  {:ok, response} ->
    # Success path

  {:error, :conversation_not_found} ->
    # Conversation expired or invalid - restart

  {:error, {:tool_execution_failed, _}} ->
    # Tool failed - may have partial response

  {:error, {:llm_request_failed, reason}} ->
    # LLM service issue - retry or fallback

  {:error, reason} ->
    # Unexpected error - log and alert
    Logger.error("Unexpected error: #{inspect(reason)}")
end
```

### 5. Conversation History Management

**Monitor and limit conversation length:**

```elixir
defmodule MyApp.ConversationGuard do
  alias Jido.AI.ReqLlmBridge.ConversationManager

  @max_messages 50
  @max_age_minutes 120

  def should_continue?(conversation_id) do
    with {:ok, metadata} <- ConversationManager.get_conversation_metadata(conversation_id) do
      message_count_ok = metadata.message_count < @max_messages
      age_ok = conversation_age_minutes(metadata) < @max_age_minutes

      message_count_ok and age_ok
    else
      _ -> false
    end
  end

  defp conversation_age_minutes(metadata) do
    DateTime.diff(DateTime.utc_now(), metadata.created_at, :minute)
  end
end

# Usage
if MyApp.ConversationGuard.should_continue?(conv_id) do
  ToolIntegrationManager.continue_conversation(conv_id, message)
else
  # Start new conversation
  ToolIntegrationManager.end_conversation(conv_id)
  {:ok, new_conv_id} = ToolIntegrationManager.start_conversation(tools, options)
end
```

### 6. Tool Timeout Configuration

**Set appropriate timeouts based on tool complexity:**

```elixir
# Fast tools (API calls, simple calculations)
fast_options = %{
  timeout: 10_000,  # 10 seconds
  max_tool_calls: 5
}

# Slow tools (data analysis, complex queries)
slow_options = %{
  timeout: 60_000,  # 60 seconds
  max_tool_calls: 2
}

# Mixed tools - set based on slowest tool
mixed_options = %{
  timeout: 45_000,
  max_tool_calls: 3
}
```

### 7. Context Passing

**Provide execution context for tools:**

```elixir
options = %{
  model: "gpt-4",
  context: %{
    user_id: "user_123",
    tenant_id: "tenant_456",
    permissions: [:read, :write],
    session_data: %{locale: "en-US"}
  }
}

{:ok, conv_id} = ToolIntegrationManager.start_conversation(
  [DatabaseQueryAction, FileAccessAction],
  options
)

# Tools can access context during execution
# This is useful for authorization, localization, etc.
```

---

## Tool Choice Strategies

The `tool_choice` option controls when and how the LLM uses tools:

### :auto (Default)

LLM decides whether to use tools based on the message:

```elixir
options = %{tool_choice: :auto}

# LLM will use weather tool
ToolIntegrationManager.generate_with_tools(
  "What's the weather in Paris?",
  [WeatherAction],
  options
)

# LLM will respond directly without tools
ToolIntegrationManager.generate_with_tools(
  "Hello, how are you?",
  [WeatherAction],
  options
)
```

### :none

LLM never uses tools, only responds with text:

```elixir
options = %{tool_choice: :none}

# LLM responds without calling weather tool
ToolIntegrationManager.generate_with_tools(
  "What's the weather in Paris?",
  [WeatherAction],
  options
)
# Response: "I don't have access to current weather data..."
```

### :required

LLM must use at least one tool:

```elixir
options = %{tool_choice: :required}

# LLM forced to call a tool
ToolIntegrationManager.generate_with_tools(
  "Tell me something interesting",
  [WeatherAction, NewsAction],
  options
)
# LLM will call one of the available tools
```

### {:function, name}

LLM must use a specific tool:

```elixir
options = %{tool_choice: {:function, "weather"}}

# LLM must call weather tool specifically
ToolIntegrationManager.generate_with_tools(
  "What's happening today?",
  [WeatherAction, CalendarAction],
  options
)
# LLM will call weather tool even if calendar might be more appropriate
```

**Use Cases**:

- `:auto` - Most common, natural tool use
- `:none` - Pure conversation without tools, or when tools are unavailable
- `:required` - Ensure tool use for data-driven responses
- `{:function, name}` - Forced execution of specific tool (testing, workflows)

---

## Streaming Responses

For long-running tool executions or real-time responses:

```elixir
defmodule MyApp.StreamingAgent do
  alias Jido.AI.ReqLlmBridge.ToolIntegrationManager

  def chat_with_streaming(conversation_id, message) do
    options = %{
      stream: true,
      timeout: 60_000
    }

    case ToolIntegrationManager.continue_conversation(
      conversation_id,
      message,
      options
    ) do
      {:ok, response} ->
        # Response includes accumulated content + tool results
        {:ok, response}

      {:error, reason} ->
        {:error, reason}
    end
  end
end

# Note: Streaming provides incremental content delivery
# Tool calls are still executed after stream completes
```

---

## Monitoring and Debugging

### Conversation Inspection

```elixir
defmodule MyApp.ConversationInspector do
  alias Jido.AI.ReqLlmBridge.{ConversationManager, ToolIntegrationManager}

  def inspect_conversation(conversation_id) do
    with {:ok, history} <- ToolIntegrationManager.get_conversation_history(conversation_id),
         {:ok, metadata} <- ConversationManager.get_conversation_metadata(conversation_id),
         {:ok, tools} <- ConversationManager.get_tools(conversation_id),
         {:ok, options} <- ConversationManager.get_options(conversation_id) do

      %{
        id: conversation_id,
        created: metadata.created_at,
        last_activity: metadata.last_activity,
        age_minutes: DateTime.diff(DateTime.utc_now(), metadata.created_at, :minute),
        message_count: metadata.message_count,
        tool_count: metadata.tool_count,
        history: format_history(history),
        tools: Enum.map(tools, & &1.name),
        options: options
      }
    end
  end

  defp format_history(history) do
    Enum.map(history, fn msg ->
      %{
        role: msg.role,
        content: String.slice(msg.content, 0, 50),
        timestamp: msg.timestamp,
        has_metadata: map_size(msg.metadata) > 0
      }
    end)
  end

  def list_all_conversations do
    {:ok, conv_ids} = ConversationManager.list_conversations()

    Enum.map(conv_ids, fn conv_id ->
      case inspect_conversation(conv_id) do
        {:ok, info} -> info
        {:error, _} -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end
end
```

### Logging

```elixir
defmodule MyApp.LoggedAgent do
  alias Jido.AI.ReqLlmBridge.ToolIntegrationManager
  require Logger

  def chat(conversation_id, message) do
    Logger.info("Processing message",
      conversation_id: conversation_id,
      message_length: String.length(message)
    )

    start_time = System.monotonic_time(:millisecond)

    result = ToolIntegrationManager.continue_conversation(conversation_id, message)

    duration = System.monotonic_time(:millisecond) - start_time

    case result do
      {:ok, response} ->
        Logger.info("Message processed successfully",
          conversation_id: conversation_id,
          duration_ms: duration,
          tool_calls: length(Map.get(response, :tool_calls, [])),
          content_length: String.length(response.content)
        )

      {:error, reason} ->
        Logger.error("Message processing failed",
          conversation_id: conversation_id,
          duration_ms: duration,
          error: inspect(reason)
        )
    end

    result
  end
end
```

---

## Advanced Topics

### Custom Tool Execution

For special tool execution requirements:

```elixir
defmodule MyApp.CustomToolExecutor do
  alias Jido.AI.ReqLlmBridge.{ConversationManager, ToolResponseHandler}

  def execute_with_validation(conversation_id, tool_calls, validation_fn) do
    # Filter tool calls based on custom validation
    validated_calls = Enum.filter(tool_calls, validation_fn)

    # Execute only validated calls
    context = %{
      conversation_id: conversation_id,
      max_tool_calls: length(validated_calls),
      timeout: 30_000,
      context: %{}
    }

    ToolResponseHandler.execute_tool_calls(validated_calls, context)
  end
end
```

### Conversation Forking

Create multiple conversation branches from a single point:

```elixir
defmodule MyApp.ConversationForker do
  alias Jido.AI.ReqLlmBridge.{ConversationManager, ToolIntegrationManager}

  def fork_conversation(source_conversation_id) do
    with {:ok, history} <- ConversationManager.get_history(source_conversation_id),
         {:ok, tools} <- ConversationManager.get_tools(source_conversation_id),
         {:ok, options} <- ConversationManager.get_options(source_conversation_id),
         {:ok, new_conv_id} <- ConversationManager.create_conversation() do

      # Copy configuration
      :ok = ConversationManager.set_tools(new_conv_id, tools)
      :ok = ConversationManager.set_options(new_conv_id, options)

      # Copy history up to this point
      Enum.each(history, fn msg ->
        case msg.role do
          "user" -> ConversationManager.add_user_message(new_conv_id, msg.content)
          "assistant" -> ConversationManager.add_assistant_response(new_conv_id, msg)
          "tool" -> :ok  # Skip tool messages for simplicity
        end
      end)

      {:ok, new_conv_id}
    end
  end
end
```

### Persistent Conversation Storage

For conversations that need to survive application restarts:

```elixir
defmodule MyApp.ConversationPersistence do
  alias Jido.AI.ReqLlmBridge.ConversationManager

  def save_conversation(conversation_id, storage_path) do
    with {:ok, history} <- ConversationManager.get_history(conversation_id),
         {:ok, tools} <- ConversationManager.get_tools(conversation_id),
         {:ok, options} <- ConversationManager.get_options(conversation_id),
         {:ok, metadata} <- ConversationManager.get_conversation_metadata(conversation_id) do

      data = %{
        conversation_id: conversation_id,
        history: history,
        tools: tools,
        options: options,
        metadata: metadata
      }

      File.write(storage_path, :erlang.term_to_binary(data))
    end
  end

  def restore_conversation(storage_path) do
    with {:ok, binary} <- File.read(storage_path),
         data = :erlang.binary_to_term(binary),
         {:ok, new_conv_id} <- ConversationManager.create_conversation() do

      # Restore configuration
      :ok = ConversationManager.set_tools(new_conv_id, data.tools)
      :ok = ConversationManager.set_options(new_conv_id, data.options)

      # Restore history
      Enum.each(data.history, fn msg ->
        case msg.role do
          "user" -> ConversationManager.add_user_message(new_conv_id, msg.content, msg.metadata)
          "assistant" -> ConversationManager.add_assistant_response(new_conv_id, msg, msg.metadata)
          "tool" -> :ok
        end
      end)

      {:ok, new_conv_id}
    end
  end
end
```

---

## Integration with Jido Agents

Using ConversationManager with Jido's agent system:

```elixir
defmodule MyApp.ConversationalAgent do
  use Jido.Agent,
    name: "conversational_agent",
    actions: [ChatAction, EndConversationAction]

  alias Jido.AI.ReqLlmBridge.ToolIntegrationManager

  @impl true
  def init(args) do
    tools = Keyword.get(args, :tools, [])
    options = Keyword.get(args, :options, %{})

    case ToolIntegrationManager.start_conversation(tools, options) do
      {:ok, conv_id} ->
        initial_state = %{
          conversation_id: conv_id,
          tools: tools,
          options: options
        }

        {:ok, initial_state}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def terminate(_reason, state) do
    ToolIntegrationManager.end_conversation(state.conversation_id)
    :ok
  end
end

# Usage
{:ok, agent} = MyApp.ConversationalAgent.new(
  tools: [WeatherAction, CalculatorAction],
  options: %{model: "gpt-4", temperature: 0.7}
)

# Agent maintains conversation state across interactions
result = Jido.Agent.cmd(agent, ChatAction, %{message: "What's the weather?"})
```

---

## Performance Optimization

### 1. Tool Execution Optimization

```elixir
# Configure parallel execution limits
options = %{
  max_tool_calls: 3,        # Limit concurrent tool calls
  timeout: 20_000           # Reduce timeout for fast tools
}

# For expensive tools, consider sequential execution
# (This requires custom implementation)
```

### 2. Conversation Cleanup

```elixir
# Manual cleanup for long-running sessions
defmodule MyApp.ConversationCleaner do
  alias Jido.AI.ReqLlmBridge.ConversationManager

  def cleanup_old_conversations(max_age_hours \\ 2) do
    {:ok, conv_ids} = ConversationManager.list_conversations()

    Enum.each(conv_ids, fn conv_id ->
      case ConversationManager.get_conversation_metadata(conv_id) do
        {:ok, metadata} ->
          age_hours = DateTime.diff(DateTime.utc_now(), metadata.last_activity, :hour)

          if age_hours > max_age_hours do
            ConversationManager.end_conversation(conv_id)
          end

        _ -> :ok
      end
    end)
  end
end

# Schedule periodic cleanup
# (In production, use a supervised task or cron job)
```

### 3. Message History Pruning

```elixir
defmodule MyApp.HistoryPruner do
  alias Jido.AI.ReqLlmBridge.ConversationManager

  def prune_old_messages(conversation_id, keep_last_n \\ 20) do
    with {:ok, history} <- ConversationManager.get_history(conversation_id) do
      if length(history) > keep_last_n do
        # Implementation would require internal access to ConversationManager
        # Consider starting a new conversation and copying recent messages
        :needs_new_conversation
      else
        :ok
      end
    end
  end
end
```

---

## Troubleshooting

### Common Issues

#### 1. Conversation Not Found

```elixir
{:error, :conversation_not_found}

# Causes:
# - Conversation ID invalid
# - Conversation expired (24 hour TTL)
# - Conversation manually ended

# Solutions:
# - Verify conversation ID
# - Check last_activity timestamp
# - Start new conversation
```

#### 2. Tool Execution Timeout

```elixir
{:error, {:tool_timeout, "Tool execution timed out"}}

# Causes:
# - Tool execution exceeds timeout (default 30s)
# - Slow external API
# - Resource contention

# Solutions:
# - Increase timeout: %{timeout: 60_000}
# - Optimize tool implementation
# - Use caching for slow operations
```

#### 3. Tool Not Found

```elixir
{:error, {:tool_not_found, "weather"}}

# Causes:
# - Tool not registered in conversation
# - Tool name mismatch
# - Tool removed after registration

# Solutions:
# - Verify tools list: get_tools(conversation_id)
# - Check tool name matches Action module name
# - Re-register tools if needed
```

#### 4. Maximum Tool Calls Exceeded

```elixir
# LLM tries to call more tools than max_tool_calls allows

# Solutions:
# - Increase limit: %{max_tool_calls: 10}
# - Review if LLM is stuck in tool-calling loop
# - Use tool_choice: :none to break loop
```

---

## Security Considerations

### 1. Tool Authorization

```elixir
defmodule MyApp.SecureToolAgent do
  alias Jido.AI.ReqLlmBridge.ToolIntegrationManager

  def create_session(user_id, requested_tools) do
    # Filter tools based on user permissions
    authorized_tools = filter_authorized_tools(user_id, requested_tools)

    options = %{
      context: %{
        user_id: user_id,
        authorized_actions: get_user_permissions(user_id)
      }
    }

    ToolIntegrationManager.start_conversation(authorized_tools, options)
  end

  defp filter_authorized_tools(user_id, tools) do
    user_permissions = get_user_permissions(user_id)

    Enum.filter(tools, fn tool ->
      tool.required_permission in user_permissions
    end)
  end

  defp get_user_permissions(user_id) do
    # Fetch from database or permission system
    [:read, :write]
  end
end
```

### 2. Input Validation

```elixir
defmodule MyApp.ValidatedAgent do
  def chat(conversation_id, message) do
    with :ok <- validate_message(message),
         :ok <- check_rate_limit(conversation_id),
         {:ok, response} <- ToolIntegrationManager.continue_conversation(
           conversation_id,
           message
         ) do
      {:ok, response}
    end
  end

  defp validate_message(message) do
    cond do
      String.length(message) > 10_000 ->
        {:error, :message_too_long}

      String.length(message) == 0 ->
        {:error, :message_empty}

      contains_malicious_content?(message) ->
        {:error, :invalid_content}

      true ->
        :ok
    end
  end

  defp check_rate_limit(conversation_id) do
    # Implement rate limiting logic
    :ok
  end

  defp contains_malicious_content?(_message) do
    # Implement content filtering
    false
  end
end
```

### 3. Data Sanitization

```elixir
defmodule MyApp.SanitizedAgent do
  def get_history(conversation_id) do
    with {:ok, history} <- ToolIntegrationManager.get_conversation_history(conversation_id) do
      sanitized = Enum.map(history, &sanitize_message/1)
      {:ok, sanitized}
    end
  end

  defp sanitize_message(message) do
    %{message |
      metadata: remove_sensitive_data(message.metadata),
      content: sanitize_content(message.content)
    }
  end

  defp remove_sensitive_data(metadata) do
    Map.drop(metadata, [:api_key, :password, :token])
  end

  defp sanitize_content(content) do
    # Remove or mask sensitive patterns
    content
    |> String.replace(~r/\b\d{3}-\d{2}-\d{4}\b/, "[SSN REDACTED]")
    |> String.replace(~r/\b\d{16}\b/, "[CARD REDACTED]")
  end
end
```

---

## Examples

Explore complete working examples:

- [Conversation Manager Examples Directory](../examples/conversation-manager/) - Complete working implementations:
  - `basic_chat.ex` - Simple multi-turn conversation with weather tool
  - `multi_tool_agent.ex` - Advanced agent with multiple tools, error handling, and state management
  - `README.md` - Comprehensive documentation and usage patterns

---

## Further Reading

- **Actions Guide**: Creating custom Jido Actions for use as tools
- **ReqLLM Documentation**: Understanding the underlying LLM client
- **Agent Guide**: Building Jido agents with conversation capabilities
- **Error Handling Guide**: Advanced error handling patterns

---

## Summary

The ConversationManager system provides a robust foundation for building stateful, tool-enabled LLM applications:

- **ConversationManager**: State storage and retrieval
- **ToolIntegrationManager**: High-level API for tool-enabled interactions
- **ToolResponseHandler**: Response processing and tool execution

Together, these components handle the complexity of multi-turn conversations with tools, allowing you to focus on building intelligent agent behaviors and user experiences.

Key takeaways:

- Always clean up conversations when done
- Configure appropriate timeouts for your tools
- Handle errors gracefully at each level
- Monitor conversation history size
- Provide context for tool authorization
- Use appropriate tool_choice strategies
- Log and monitor for production deployments
