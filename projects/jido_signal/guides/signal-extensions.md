# Signal Extensions

Signal extensions provide a way to add domain-specific metadata to Signals while maintaining CloudEvents v1.0.2 compliance. Extensions allow you to enrich Signals with custom functionality without modifying the core Signal structure.

## Why Extensions?

Extensions solve the problem of adding custom metadata to Signals:

- **Structured Metadata**: Type-safe, validated custom data
- **CloudEvents Compliance**: Extensions become top-level CloudEvents attributes
- **Composable**: Multiple extensions can work together on a single Signal
- **Backward Compatible**: Signals without extensions work unchanged

Common use cases include:
- **Threading**: Track conversation threads in LLM systems
- **Tracing**: Add distributed tracing context
- **Security**: Include authentication/authorization data
- **Routing**: Custom dispatch configurations

## Creating an Extension

Extensions are defined using the `Jido.Signal.Ext` behavior. Let's create a simple example:

```elixir
defmodule MyApp.Signal.Ext.Thread do
  @moduledoc """
  Extension for tracking conversation threads in LLM interactions.
  """
  
  use Jido.Signal.Ext,
    namespace: "thread",
    schema: [
      id: [type: :string, required: true, doc: "Unique thread identifier"],
      parent_id: [type: :string, doc: "Parent message ID for threading"]
    ]
end
```

That's it! The extension automatically:
- Registers itself in the extension registry
- Validates data using the schema
- Provides serialization to CloudEvents format
- Handles deserialization back to structured data

## Using Extensions

Add extension data to a Signal:

```elixir
alias MyApp.Signal.Ext.Thread

# Create a Signal
{:ok, signal} = Jido.Signal.new("llm.conversation.message", 
  %{content: "Hello, how can I help?", role: "assistant"},
  source: "/chat/session"
)

# Add thread extension
{:ok, signal_with_thread} = Jido.Signal.put_extension(signal, Thread, %{
  id: "thread-123",
  parent_id: "msg-456" 
})
```

Retrieve extension data:

```elixir
thread_data = Jido.Signal.get_extension(signal_with_thread, Thread)
# => %{id: "thread-123", parent_id: "msg-456"}
```

List all extensions on a Signal:

```elixir
extensions = Jido.Signal.list_extensions(signal_with_thread)
# => [MyApp.Signal.Ext.Thread]
```

Remove an extension:

```elixir
signal_without_thread = Jido.Signal.delete_extension(signal_with_thread, Thread)
```

## Built-in Dispatch Extension

Jido.Signal includes a built-in Dispatch extension that provides the same functionality as the legacy `jido_dispatch` field:

```elixir
alias Jido.Signal.Ext.Dispatch

# Add dispatch configuration via extension
{:ok, signal} = Jido.Signal.put_extension(signal, Dispatch, 
  {:pubsub, topic: "chat-events"}
)

# Multiple dispatch targets
{:ok, signal} = Jido.Signal.put_extension(signal, Dispatch, [
  {:pubsub, topic: "events"},
  {:logger, level: :info}
])
```

## CloudEvents Serialization

Extensions automatically serialize to CloudEvents-compliant top-level attributes:

```elixir
# Signal with thread extension
signal = %Jido.Signal{
  type: "llm.conversation.message",
  source: "/chat",
  data: %{content: "Hello"},
  extensions: %{
    "thread" => %{id: "thread-123", parent_id: "msg-456"}
  }
}

# Serializes to CloudEvents JSON:
{:ok, json} = Jido.Signal.serialize(signal)
```

Results in:
```json
{
  "specversion": "1.0.2",
  "type": "llm.conversation.message", 
  "source": "/chat",
  "id": "...",
  "data": {"content": "Hello"},
  "threadid": "thread-123",
  "parentid": "msg-456"
}
```

## Custom Serialization

For more control over how extensions serialize, override the `to_attrs/1` and `from_attrs/1` callbacks:

```elixir
defmodule MyApp.Signal.Ext.CustomTrace do
  use Jido.Signal.Ext,
    namespace: "trace",
    schema: [
      trace_id: [type: :string, required: true],
      span_id: [type: :string, required: true],
      parent_span_id: [type: :string]
    ]

  # Custom serialization - multiple CloudEvents attributes
  def to_attrs(%{trace_id: trace_id, span_id: span_id, parent_span_id: parent_span_id}) do
    attrs = %{
      "traceid" => trace_id,
      "spanid" => span_id
    }
    
    if parent_span_id do
      Map.put(attrs, "parentspan", parent_span_id)
    else
      attrs
    end
  end

  # Custom deserialization  
  def from_attrs(attrs) do
    case Map.get(attrs, "traceid") do
      nil -> {:ok, nil}
      trace_id ->
        {:ok, %{
          trace_id: trace_id,
          span_id: Map.get(attrs, "spanid"),
          parent_span_id: Map.get(attrs, "parentspan")
        }}
    end
  end
end
```

## Multiple Extensions

Signals can have multiple extensions simultaneously:

```elixir
{:ok, signal} = Jido.Signal.new("user.action", %{action: "login"})

# Add multiple extensions
{:ok, signal} = signal 
  |> Jido.Signal.put_extension(Thread, %{id: "session-123"})
  |> elem(1)
  |> Jido.Signal.put_extension(CustomTrace, %{
       trace_id: "trace-abc", 
       span_id: "span-def"
     })

# All extensions are preserved during serialization/deserialization
{:ok, json} = Jido.Signal.serialize(signal)
{:ok, deserialized_signal} = Jido.Signal.deserialize(json)

# Extensions are fully restored
thread_data = Jido.Signal.get_extension(deserialized_signal, Thread)
trace_data = Jido.Signal.get_extension(deserialized_signal, CustomTrace)
```

## Extension Guidelines

### Namespace Rules
- Use lowercase names with optional dots (e.g., "auth", "trace", "auth.oauth")
- Keep names ≤ 20 characters (CloudEvents requirement)
- Only use `[a-z0-9]` characters (CloudEvents requirement)

### Schema Design
- Use NimbleOptions schema format
- Mark required fields with `required: true`
- Add documentation with `doc:` option
- Keep data structures simple for serialization

### Example Patterns

**Authentication Context:**
```elixir
defmodule MyApp.Signal.Ext.Auth do
  use Jido.Signal.Ext,
    namespace: "auth",
    schema: [
      user_id: [type: :string, required: true],
      permissions: [type: {:list, :string}, default: []],
      session_id: [type: :string]
    ]
end
```

**Metrics Collection:**
```elixir
defmodule MyApp.Signal.Ext.Metrics do
  use Jido.Signal.Ext,
    namespace: "metrics", 
    schema: [
      duration_ms: [type: :integer],
      memory_kb: [type: :integer],
      tags: [type: :keyword_list, default: []]
    ]
end
```

## Testing Extensions

Test extensions like any other module:

```elixir
defmodule MyApp.Signal.Ext.ThreadTest do
  use ExUnit.Case, async: true

  alias MyApp.Signal.Ext.Thread

  test "validates required fields" do
    assert {:ok, _} = Thread.new(%{id: "thread-123"})
    assert {:error, _} = Thread.new(%{parent_id: "msg-456"}) # missing id
  end

  test "serialization round-trip" do
    data = %{id: "thread-123", parent_id: "msg-456"}
    
    # Serialize
    attrs = Thread.to_attrs(data)
    
    # Deserialize  
    {:ok, restored_data} = Thread.from_attrs(attrs)
    
    assert data == restored_data
  end
end
```

## Best Practices

1. **Keep Extensions Simple**: Focus on single responsibility
2. **Validate Early**: Use comprehensive schemas to catch errors
3. **Test Serialization**: Always test round-trip serialization
4. **Document Usage**: Provide clear examples in moduledocs
5. **Consider CloudEvents**: Ensure attribute names follow CloudEvents rules
6. **Backward Compatibility**: Design for evolution - avoid breaking changes

Extensions provide a powerful way to add domain-specific functionality to Signals while maintaining standardization and interoperability. They're the key to building sophisticated event-driven systems that scale from simple applications to complex distributed architectures.
