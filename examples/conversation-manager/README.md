# Conversation Manager Examples

This directory contains practical examples demonstrating the ConversationManager system for stateful, multi-turn tool-enabled conversations with Jido AI.

## What is Conversation Manager?

The ConversationManager system provides infrastructure for building stateful LLM applications that maintain context across multiple conversation turns and can use tools (function calling). It consists of three coordinated components:

- **ConversationManager**: State storage and message history
- **ToolIntegrationManager**: High-level API for tool-enabled interactions
- **ToolResponseHandler**: Response processing and tool execution

## Performance

| Aspect | Details |
|--------|---------|
| **Storage** | In-memory ETS tables |
| **Concurrency** | Thread-safe, multiple conversations |
| **Cleanup** | Auto-expire after 24 hours |
| **Tool Execution** | Parallel (4 concurrent), 30s timeout |

## Examples

### 1. Basic Chat (`basic_chat.ex`)

**Purpose**: Demonstrates basic multi-turn conversation with tool integration.

**Features**:
- Starting a conversation with tools
- Multiple conversation turns
- Tool execution (weather lookups)
- Conversation history tracking
- Proper cleanup

**The Classic Use Case**: Weather Assistant
```
User: "What's the weather like in Paris?"
Assistant: [Calls weather tool] "It's 18°C and partly cloudy"
User: "And what about London?"
Assistant: [Uses context + calls tool] "London is 15°C and rainy"
User: "Which city is warmer?"
Assistant: [Uses conversation history] "Paris is warmer at 18°C vs London's 15°C"
```

**Usage**:
```elixir
# Run the example
Examples.ConversationManager.BasicChat.run()

# Use the functions directly
{:ok, conv_id} = Examples.ConversationManager.BasicChat.start_chat([WeatherAction])
{:ok, response} = Examples.ConversationManager.BasicChat.chat(conv_id, "What's the weather?")
{:ok, history} = Examples.ConversationManager.BasicChat.get_history(conv_id)
:ok = Examples.ConversationManager.BasicChat.end_chat(conv_id)
```

**Example Output**:
```
📝 **Example:** Weather Assistant with Conversation History

🔧 **Starting conversation with WeatherAction...**
✓ Conversation started: 1a2b3c4d...

💬 **User:** What's the weather like in Paris?

🤖 **Assistant (Turn 1):**
   The current weather in Paris is 18°C and partly cloudy.

   🔧 Tool Calls Made:
      • get_weather(location: "Paris")

   📊 Tokens Used: 145

💬 **User:** And what about London?

🤖 **Assistant (Turn 2):**
   London is currently 15°C with rainy conditions.

   🔧 Tool Calls Made:
      • get_weather(location: "London")

💬 **User:** Which city is warmer?

🤖 **Assistant (Turn 3):**
   Based on our previous checks, Paris is warmer at 18°C compared to London's 15°C.

📜 **Conversation History:**
   Total messages: 6

   1. 👤 User
      "What's the weather like in Paris?"
      ⏰ 10:15:23

   2. 🤖 Assistant
      "The current weather in Paris is 18°C and partly cloudy."
      ⏰ 10:15:24

   ...
```

**Key Concepts**:
- Conversation lifecycle (start, chat, end)
- Stateful context across turns
- Tool execution with result display
- History tracking and retrieval

**Best For**:
- Learning ConversationManager basics
- Simple multi-turn conversations
- Understanding conversation state
- Single-tool use cases

---

### 2. Multi-Tool Agent (`multi_tool_agent.ex`)

**Purpose**: Demonstrates advanced conversation patterns with multiple tools and sophisticated state management.

**Features**:
- Multiple tool integration (Weather, Calculator, Search)
- Error handling and retry logic
- Conversation metadata tracking
- History analysis and statistics
- Tool usage analytics
- Response time measurement
- Agent state inspection

**Advanced Use Case**: Multi-Tool Assistant
```
User: "What's the weather in Paris? Also calculate temp in Fahrenheit if it's 18 Celsius."
Assistant: [Calls weather + calculator tools]
   "Paris is 18°C (64°F) and partly cloudy"

User: "Search for capital of Japan, then tell me weather there"
Assistant: [Calls search, then weather tool]
   "Tokyo is the capital of Japan. Current weather: 22°C and clear"
```

**Usage**:
```elixir
# Run the full example
Examples.ConversationManager.MultiToolAgent.run()

# Create a custom agent
{:ok, agent} = Examples.ConversationManager.MultiToolAgent.create_agent(%{
  tools: [WeatherAction, CalculatorAction, SearchAction],
  options: %{
    model: "gpt-4",
    temperature: 0.7,
    max_tool_calls: 10,
    timeout: 30_000
  }
})

# Process messages
{:ok, response, updated_agent} = Examples.ConversationManager.MultiToolAgent.process(
  agent,
  "What's 15 * 23 and what's the weather in Tokyo?",
  retries: 2,
  log: true
)

# Get conversation statistics
{:ok, stats} = Examples.ConversationManager.MultiToolAgent.get_statistics(agent)
IO.inspect(stats)
# %{
#   conversation_id: "...",
#   age_minutes: 5,
#   total_messages: 12,
#   user_messages: 4,
#   assistant_messages: 4,
#   tool_messages: 4,
#   tools_available: 3,
#   tool_names: ["get_weather", "calculate", "search"]
# }

# Analyze conversation patterns
{:ok, analysis} = Examples.ConversationManager.MultiToolAgent.analyze_conversation(agent)
IO.inspect(analysis)
# %{
#   tool_usage: %{"get_weather" => 2, "calculate" => 1},
#   avg_response_time: 2.3,
#   conversation_flow: ...
# }

# Cleanup
:ok = Examples.ConversationManager.MultiToolAgent.destroy_agent(agent)
```

**Example Output**:
```
📝 **Example:** Advanced agent with multiple tools and error handling

🔧 **Creating agent with 3 tools...**
✓ Agent created successfully

   ID: 1a2b3c4d5e6f7g8h...
   Tools: 3
      • get_weather
      • calculate
      • search
   Model: gpt-4
   Temperature: 0.7
   Max Tool Calls: 10
   Timeout: 30000ms

🎯 **Running Conversation Scenarios**

📍 **Scenario 1: Weather + Calculation**
   User: What's the weather in Paris? Also calculate...

   🤖 Assistant: Paris is 18°C (64°F) and partly cloudy.
   🔧 Tools Used: 2
      • get_weather
      • calculate
   ⏱️  Duration: 1250ms

📍 **Scenario 2: Search + Weather**
   User: Search for the capital of Japan...

   🤖 Assistant: Tokyo is the capital. Weather: 22°C, clear.
   🔧 Tools Used: 2
      • search
      • get_weather
   ⏱️  Duration: 1180ms

📊 **Final Statistics**

   Conversation Age: 0 minutes
   Total Messages: 16
      • User: 4
      • Assistant: 4
      • Tool: 8
   Tools Available: 3

📈 **Conversation Analysis:**

   Tool Usage Breakdown:
      • get_weather: 3 calls
      • calculate: 2 calls
      • search: 1 call

   Avg Response Time: 1.2s

✓ Agent destroyed successfully
```

**Advanced Features**:

1. **Error Handling with Retry**:
```elixir
# Automatic retry on LLM failures
{:ok, response, agent} = MultiToolAgent.process(
  agent,
  message,
  retries: 3  # Retry up to 3 times
)
```

2. **Conversation Statistics**:
```elixir
{:ok, stats} = MultiToolAgent.get_statistics(agent)
# Returns comprehensive stats: message counts, age, tools, etc.
```

3. **Tool Usage Analytics**:
```elixir
{:ok, analysis} = MultiToolAgent.analyze_conversation(agent)
# Tool usage frequency, response times, conversation patterns
```

4. **Custom Agent Configuration**:
```elixir
agent = MultiToolAgent.create_agent(%{
  tools: [WeatherAction, DatabaseAction],
  options: %{
    model: "gpt-4",
    temperature: 0.9,          # More creative
    max_tool_calls: 15,        # Allow more tools
    timeout: 60_000,           # Longer timeout
    context: %{                # Pass context to tools
      user_id: "user_123",
      permissions: [:read, :write]
    }
  }
})
```

**Key Concepts**:
- Agent-based conversation management
- Multi-tool coordination
- Error handling and recovery
- Conversation analytics
- Performance monitoring
- Stateful agent updates

**Best For**:
- Production-grade implementations
- Multi-tool applications
- Error handling patterns
- Conversation monitoring
- Performance analysis
- Complex agent behaviors

---

## Quick Start

### Running Examples in IEx

```elixir
# Start IEx
iex -S mix

# Compile examples
c "examples/conversation-manager/basic_chat.ex"
c "examples/conversation-manager/multi_tool_agent.ex"

# Run examples
Examples.ConversationManager.BasicChat.run()
Examples.ConversationManager.MultiToolAgent.run()
```

### Running from Mix Task

```bash
# Run basic chat
mix run -e "Examples.ConversationManager.BasicChat.run()"

# Run multi-tool agent
mix run -e "Examples.ConversationManager.MultiToolAgent.run()"
```

## Comparison: Basic vs Advanced Examples

| Aspect | Basic Chat | Multi-Tool Agent |
|--------|-----------|------------------|
| **Complexity** | Simple | Advanced |
| **Tools** | 1 (Weather) | 3 (Weather, Calculator, Search) |
| **Error Handling** | Basic | Retry logic + recovery |
| **Analytics** | History display | Full statistics + analysis |
| **State Management** | Conversation ID | Agent struct with metadata |
| **Monitoring** | None | Response times, tool usage |
| **Best For** | Learning | Production |

## Common Patterns

### Pattern 1: Simple Conversation Lifecycle

Used in: `basic_chat.ex`

```elixir
def simple_conversation_pattern do
  # 1. Start conversation with tools
  {:ok, conv_id} = ToolIntegrationManager.start_conversation(
    [WeatherAction],
    %{model: "gpt-4"}
  )

  # 2. Chat multiple turns
  {:ok, response1} = ToolIntegrationManager.continue_conversation(
    conv_id,
    "First message"
  )

  {:ok, response2} = ToolIntegrationManager.continue_conversation(
    conv_id,
    "Second message"
  )

  # 3. Get history
  {:ok, history} = ToolIntegrationManager.get_conversation_history(conv_id)

  # 4. Cleanup
  :ok = ToolIntegrationManager.end_conversation(conv_id)
end
```

### Pattern 2: Agent-Based Management

Used in: `multi_tool_agent.ex`

```elixir
def agent_based_pattern do
  # 1. Create agent (encapsulates conversation + config)
  {:ok, agent} = MultiToolAgent.create_agent(%{
    tools: [WeatherAction, CalculatorAction],
    options: %{model: "gpt-4"}
  })

  # 2. Process with agent (automatic state updates)
  {:ok, response, updated_agent} = MultiToolAgent.process(
    agent,
    "Message",
    retries: 2
  )

  # 3. Get analytics
  {:ok, stats} = MultiToolAgent.get_statistics(updated_agent)

  # 4. Cleanup
  :ok = MultiToolAgent.destroy_agent(updated_agent)
end
```

### Pattern 3: Error Handling

Used in: `multi_tool_agent.ex`

```elixir
def error_handling_pattern(agent, message) do
  case MultiToolAgent.process(agent, message, retries: 3) do
    {:ok, response, updated_agent} ->
      # Success
      {:ok, response}

    {:error, :max_retries_exceeded} ->
      # All retries failed
      {:error, :service_unavailable}

    {:error, :tool_execution_failed} ->
      # Tools failed, but may have partial response
      {:error, :partial_failure}

    {:error, reason} ->
      # Other errors
      Logger.error("Unexpected error: #{inspect(reason)}")
      {:error, reason}
  end
end
```

### Pattern 4: History Analysis

Used in: Both examples

```elixir
def history_analysis_pattern(conversation_id) do
  {:ok, history} = ToolIntegrationManager.get_conversation_history(conversation_id)

  # Count messages by role
  user_count = Enum.count(history, &(&1.role == "user"))
  assistant_count = Enum.count(history, &(&1.role == "assistant"))
  tool_count = Enum.count(history, &(&1.role == "tool"))

  # Extract tool usage
  tool_names = Enum.filter(history, &(&1.role == "tool"))
                |> Enum.map(&get_in(&1, [:metadata, :tool_name]))
                |> Enum.frequencies()

  %{
    user_messages: user_count,
    assistant_messages: assistant_count,
    tool_calls: tool_count,
    tool_usage: tool_names
  }
end
```

### Pattern 5: Resource Cleanup

Used in: Both examples

```elixir
def with_conversation(tools, opts, fun) do
  {:ok, conv_id} = ToolIntegrationManager.start_conversation(tools, opts)

  try do
    fun.(conv_id)
  after
    ToolIntegrationManager.end_conversation(conv_id)
  end
end

# Usage
with_conversation([WeatherAction], %{}, fn conv_id ->
  ToolIntegrationManager.continue_conversation(conv_id, "Hello!")
end)
```

## Tips for Using These Examples

1. **Start with basic_chat.ex**: Understand the fundamentals before moving to advanced patterns
2. **Experiment with tools**: Add your own Action modules to see how tools integrate
3. **Monitor statistics**: Use the analytics functions to understand conversation patterns
4. **Handle errors**: Implement retry logic for production robustness
5. **Manage history**: Keep conversations short or implement history pruning
6. **Configure timeouts**: Adjust based on your tool execution times
7. **Use context**: Pass execution context for authorization and customization

## When to Use Each Pattern

### Use Basic Chat (`basic_chat.ex`) For:
- Learning ConversationManager basics
- Simple Q&A applications
- Single-tool use cases
- Straightforward multi-turn conversations
- Quick prototypes and demos

### Use Multi-Tool Agent (`multi_tool_agent.ex`) For:
- Production applications
- Multiple tool coordination
- Error-resilient systems
- Conversation analytics
- Performance monitoring
- Complex agent behaviors
- Systems requiring conversation insights

## Integration with Jido Agents

These examples can be integrated into Jido Agents:

```elixir
defmodule MyConversationalAgent do
  use Jido.Agent,
    name: "conversational_assistant",
    actions: [ChatAction]

  @impl true
  def init(args) do
    tools = Keyword.get(args, :tools, [])

    {:ok, conv_id} = ToolIntegrationManager.start_conversation(
      tools,
      %{model: "gpt-4"}
    )

    {:ok, %{conversation_id: conv_id, tools: tools}}
  end

  @impl true
  def terminate(_reason, state) do
    ToolIntegrationManager.end_conversation(state.conversation_id)
    :ok
  end
end
```

## Further Reading

- [Conversation Manager Guide](../../guides/conversation_manager.md) - Complete documentation
- [Actions Guide](../../guides/actions.md) - Creating custom Jido Actions
- [ReqLLM Documentation](https://hexdocs.pm/req_llm) - Understanding the LLM client

## Contributing

To add new examples:

1. Create a new file in this directory
2. Follow the existing patterns (basic vs advanced)
3. Include comprehensive documentation
4. Add usage examples in module docs
5. Update this README with the new example
6. Add tests if applicable

## Questions?

See the main [Conversation Manager Guide](../../guides/conversation_manager.md) for detailed documentation on:
- Complete API reference
- Advanced patterns and techniques
- Security considerations
- Performance optimization
- Troubleshooting common issues
