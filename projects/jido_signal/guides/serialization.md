# Serialization

Comprehensive guide to signal serialization, including built-in serializers, custom implementations, and security considerations.

## Overview

Jido Signal provides a flexible serialization system that allows signals to be converted to binary format for storage, transmission, or inter-process communication. The system supports multiple serialization formats and is designed to be extensible with custom serializers.

### Serializer Behaviour

All serializers implement the `Jido.Signal.Serialization.Serializer` behaviour:

```elixir
@behaviour Jido.Signal.Serialization.Serializer

def serialize(data, opts \\ []) do
  # Convert data to binary format
  {:ok, binary}
end

def deserialize(binary, opts \\ []) do
  # Convert binary back to original data
  {:ok, data}
end
```

## Built-in Serializers

### JSON Serializer (Default)

Uses the Jason library for JSON serialization. Best for web APIs and human-readable formats.

```elixir
alias Jido.Signal.Serialization.JsonSerializer

# Basic usage
{:ok, signal} = Jido.Signal.new(%{type: "user.created", source: "/auth"})
{:ok, json} = JsonSerializer.serialize(signal)
{:ok, deserialized} = JsonSerializer.deserialize(json)
```

**Features:**
- Human-readable format
- Wide platform compatibility
- Automatic type conversion via JsonDecoder protocol
- Support for nested data structures

**Limitations:**
- Atoms converted to strings
- No tuple support
- Precision loss for some numeric types

### MessagePack Serializer

Compact binary format ideal for network transmission and storage efficiency.

```elixir
alias Jido.Signal.Serialization.MsgpackSerializer

# Configure as default
config :jido, :default_serializer, MsgpackSerializer

# Explicit usage
{:ok, binary} = Signal.serialize(signal, serializer: MsgpackSerializer)
{:ok, result} = Signal.deserialize(binary, serializer: MsgpackSerializer)
```

**Features:**
- Compact binary format (smaller than JSON)
- Fast serialization/deserialization
- Cross-platform compatibility
- Better type preservation than JSON

**Limitations:**
- Atoms converted to strings
- Tuples converted to arrays with special tagging
- Requires Msgpax dependency

### Erlang Term Serializer

Native Erlang binary format preserving exact data types. Perfect for Elixir/Erlang distributed systems.

```elixir
alias Jido.Signal.Serialization.ErlangTermSerializer

# Best for inter-node communication
{:ok, binary} = Signal.serialize(signal, serializer: ErlangTermSerializer)
{:ok, exact_copy} = Signal.deserialize(binary, serializer: ErlangTermSerializer)
```

**Features:**
- Preserves exact Elixir/Erlang data types
- Most efficient for Erlang ecosystem
- Automatic compression
- Perfect round-trip fidelity

**Limitations:**
- Only compatible with Erlang/Elixir systems
- Binary format not human-readable
- Security considerations with `:safe` option

## Configuration

### Default Serializer

Configure the default serializer in your application config:

```elixir
# config/config.exs
config :jido,
  default_serializer: Jido.Signal.Serialization.JsonSerializer,
  default_type_provider: Jido.Signal.Serialization.ModuleNameTypeProvider
```

Available serializers:
- `Jido.Signal.Serialization.JsonSerializer` (default)
- `Jido.Signal.Serialization.MsgpackSerializer`
- `Jido.Signal.Serialization.ErlangTermSerializer`

### Runtime Configuration

Change serializer configuration at runtime:

```elixir
alias Jido.Signal.Serialization.Config

# Change default serializer
Config.set_default_serializer(MsgpackSerializer)

# Verify current configuration
Config.validate()
# => :ok or {:error, [error_messages]}

# Get all configuration
Config.all()
# => [default_serializer: JsonSerializer, default_type_provider: ModuleNameTypeProvider]
```

### Per-Signal Overrides

Override serializer for specific operations:

```elixir
# Use different serializer for this operation only
{:ok, binary} = Signal.serialize(signal, serializer: ErlangTermSerializer)
{:ok, result} = Signal.deserialize(binary, serializer: ErlangTermSerializer)

# Signal retains default serializer for other operations
{:ok, json} = Signal.serialize(signal)  # Uses default JsonSerializer
```

## Type Providers and Module Name Encoding

### Type Provider Behaviour

Type providers convert between Elixir structs and string representations:

```elixir
@behaviour Jido.Signal.Serialization.TypeProvider

def to_string(struct) do
  # Convert struct to type string
  "MyApp.Events.UserCreated"
end

def to_struct(type_string) do
  # Convert type string back to struct
  MyApp.Events.UserCreated
end
```

### Module Name Type Provider (Default)

Uses Elixir module names as type identifiers:

```elixir
alias Jido.Signal.Serialization.ModuleNameTypeProvider

# Convert struct to type string
ModuleNameTypeProvider.to_string(%MyApp.Events.UserCreated{})
# => "Elixir.MyApp.Events.UserCreated"

# Convert type string to struct
ModuleNameTypeProvider.to_struct("Elixir.MyApp.Events.UserCreated")
# => MyApp.Events.UserCreated
```

### Type-Aware Deserialization

Deserialize to specific types using type information:

```elixir
# Serialize with type information preserved
defmodule UserCreatedEvent do
  defstruct [:user_id, :email]
end

event = %UserCreatedEvent{user_id: "123", email: "user@example.com"}
{:ok, json} = JsonSerializer.serialize(event)

# Deserialize back to specific struct
{:ok, restored} = JsonSerializer.deserialize(json, 
  type: "Elixir.UserCreatedEvent",
  type_provider: ModuleNameTypeProvider
)

assert %UserCreatedEvent{} = restored
```

## Custom Serializer Implementation

### Basic Custom Serializer

Implement the Serializer behaviour for custom formats:

```elixir
defmodule MyApp.Serialization.XmlSerializer do
  @behaviour Jido.Signal.Serialization.Serializer

  def serialize(data, opts \\ []) do
    try do
      xml = convert_to_xml(data)
      {:ok, xml}
    rescue
      e -> {:error, Exception.message(e)}
    end
  end

  def deserialize(binary, opts \\ []) do
    try do
      data = parse_xml(binary)
      {:ok, data}
    rescue
      e -> {:error, Exception.message(e)}
    end
  end

  defp convert_to_xml(data) do
    # Your XML conversion logic
  end

  defp parse_xml(xml) do
    # Your XML parsing logic
  end
end
```

### Advanced Custom Serializer

Support type conversion and validation:

```elixir
defmodule MyApp.Serialization.ProtobufSerializer do
  @behaviour Jido.Signal.Serialization.Serializer
  
  alias Jido.Signal.Serialization.TypeProvider

  def serialize(data, opts \\ []) do
    try do
      # Convert to protobuf message
      proto_data = to_protobuf(data)
      encoded = MyProtos.Signal.encode(proto_data)
      {:ok, encoded}
    rescue
      e -> {:error, Exception.message(e)}
    end
  end

  def deserialize(binary, opts \\ []) do
    try do
      decoded = MyProtos.Signal.decode(binary)
      
      # Handle type conversion if specified
      result = case Keyword.get(opts, :type) do
        nil -> 
          from_protobuf(decoded)
        type_str ->
          type_provider = Keyword.get(opts, :type_provider, TypeProvider)
          target_struct = type_provider.to_struct(type_str)
          from_protobuf(decoded, target_struct)
      end
      
      {:ok, result}
    rescue
      e -> {:error, Exception.message(e)}
    end
  end

  defp to_protobuf(data), do: # conversion logic
  defp from_protobuf(proto), do: # conversion logic
  defp from_protobuf(proto, target_struct), do: # typed conversion
end
```

### Custom JsonDecoder Implementation

Extend JSON deserialization with custom post-processing:

```elixir
defmodule MyApp.Events.UserCreated do
  defstruct [:user_id, :email, :created_at]
end

defimpl Jido.Signal.Serialization.JsonDecoder, for: MyApp.Events.UserCreated do
  def decode(%{created_at: timestamp} = data) when is_binary(timestamp) do
    # Convert ISO string to DateTime
    {:ok, datetime, _} = DateTime.from_iso8601(timestamp)
    %{data | created_at: datetime}
  end

  def decode(data), do: data
end
```

## Security and Validation Considerations

### Untrusted Payload Security

When deserializing untrusted data, implement proper validation:

```elixir
defmodule SecureDeserializer do
  def safe_deserialize(binary, allowed_types \\ []) do
    with {:ok, data} <- JsonSerializer.deserialize(binary),
         :ok <- validate_structure(data),
         :ok <- validate_type(data, allowed_types) do
      {:ok, data}
    else
      {:error, reason} -> {:error, {:validation_failed, reason}}
    end
  end

  defp validate_structure(data) do
    required_fields = [:type, :source, :id]
    
    if Enum.all?(required_fields, &Map.has_key?(data, &1)) do
      :ok
    else
      {:error, :missing_required_fields}
    end
  end

  defp validate_type(%{type: type}, allowed_types) when length(allowed_types) > 0 do
    if type in allowed_types do
      :ok
    else
      {:error, {:disallowed_type, type}}
    end
  end

  defp validate_type(_, []), do: :ok
end
```

### Input Sanitization

Sanitize data before deserialization:

```elixir
defmodule DataSanitizer do
  def sanitize_for_deserialization(binary) when is_binary(binary) do
    # Limit size to prevent memory exhaustion
    max_size = 1_048_576  # 1MB
    
    if byte_size(binary) > max_size do
      {:error, :payload_too_large}
    else
      validate_encoding(binary)
    end
  end

  defp validate_encoding(binary) do
    case String.valid?(binary) do
      true -> {:ok, binary}
      false -> {:error, :invalid_encoding}
    end
  end
end
```

### Safe Erlang Term Deserialization

When using ErlangTermSerializer with untrusted data:

```elixir
defmodule SafeErlangDeserializer do
  def safe_deserialize(binary) do
    try do
      # Use :safe option to prevent code execution
      term = :erlang.binary_to_term(binary, [:safe])
      validate_term(term)
    rescue
      _ -> {:error, :invalid_erlang_term}
    end
  end

  defp validate_term(term) do
    # Implement additional validation as needed
    case term do
      %_{} = struct -> validate_struct(struct)
      data when is_map(data) -> {:ok, data}
      _ -> {:error, :unsupported_term_type}
    end
  end

  defp validate_struct(%module{} = struct) do
    # Only allow known struct types
    allowed_modules = [Jido.Signal, MyApp.Events.UserCreated]
    
    if module in allowed_modules do
      {:ok, struct}
    else
      {:error, {:disallowed_struct, module}}
    end
  end
end
```

## Interoperability and Versioning

### Content-Type Headers

Use appropriate content-type headers for different serializers:

```elixir
defmodule SerializationHelpers do
  def content_type_for_serializer(JsonSerializer), do: "application/json"
  def content_type_for_serializer(MsgpackSerializer), do: "application/msgpack"
  def content_type_for_serializer(ErlangTermSerializer), do: "application/x-erlang-binary"
  def content_type_for_serializer(_), do: "application/octet-stream"

  def serializer_for_content_type("application/json"), do: JsonSerializer
  def serializer_for_content_type("application/msgpack"), do: MsgpackSerializer
  def serializer_for_content_type("application/x-erlang-binary"), do: ErlangTermSerializer
  def serializer_for_content_type(_), do: JsonSerializer  # Default fallback
end
```

### Version-Aware Serialization

Handle schema evolution and backward compatibility:

```elixir
defmodule VersionedSerialization do
  @current_version "1.2.0"

  def serialize_with_version(data, opts \\ []) do
    versioned_data = Map.put(data, :schema_version, @current_version)
    JsonSerializer.serialize(versioned_data, opts)
  end

  def deserialize_with_migration(binary, opts \\ []) do
    with {:ok, data} <- JsonSerializer.deserialize(binary, opts),
         {:ok, migrated} <- migrate_to_current_version(data) do
      {:ok, migrated}
    end
  end

  defp migrate_to_current_version(%{schema_version: version} = data) do
    case version do
      "1.0.0" -> migrate_1_0_to_1_2(data)
      "1.1.0" -> migrate_1_1_to_1_2(data)
      "1.2.0" -> {:ok, data}
      _ -> {:error, {:unsupported_version, version}}
    end
  end

  defp migrate_to_current_version(data) do
    # No version field means legacy format
    migrate_legacy_to_1_2(data)
  end

  defp migrate_1_0_to_1_2(data) do
    # Implement migration logic
    {:ok, Map.put(data, :schema_version, "1.2.0")}
  end

  defp migrate_1_1_to_1_2(data) do
    # Implement migration logic
    {:ok, Map.put(data, :schema_version, "1.2.0")}
  end

  defp migrate_legacy_to_1_2(data) do
    # Implement legacy migration
    {:ok, Map.put(data, :schema_version, "1.2.0")}
  end
end
```

### Cross-Platform Considerations

Design serialization for cross-platform compatibility:

```elixir
defmodule CrossPlatformSignal do
  @derive Jason.Encoder
  defstruct [
    :type,
    :source, 
    :id,
    :time,          # Always ISO 8601 string
    :data,          # Avoid atoms, use string keys
    :metadata       # Platform-specific extensions
  ]

  def new(attrs) do
    %__MODULE__{
      type: attrs[:type],
      source: attrs[:source], 
      id: attrs[:id] || UUID.uuid4(),
      time: attrs[:time] || DateTime.utc_now() |> DateTime.to_iso8601(),
      data: ensure_string_keys(attrs[:data] || %{}),
      metadata: attrs[:metadata] || %{}
    }
  end

  defp ensure_string_keys(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {to_string(k), v} end)
  end

  defp ensure_string_keys(data), do: data
end
```

## Performance Considerations

### Serializer Comparison

Different serializers have different performance characteristics:

```elixir
# Size comparison (smallest to largest)
ErlangTermSerializer < MsgpackSerializer < JsonSerializer

# Speed comparison (fastest to slowest for Elixir data)
ErlangTermSerializer > MsgpackSerializer > JsonSerializer

# Compatibility (most to least compatible)
JsonSerializer > MsgpackSerializer > ErlangTermSerializer
```

### Optimization Tips

1. **Choose the right serializer for your use case:**
   - JSON for web APIs and human-readable data
   - MessagePack for size-constrained networks
   - Erlang Term for Elixir/Erlang distributed systems

2. **Minimize data size:**
   ```elixir
   # Instead of including all signal fields
   full_signal = %Signal{type: "event", source: "/app", data: data, time: time, ...}
   
   # Consider minimal payloads for performance-critical paths
   minimal_payload = %{type: "event", data: data}
   ```

3. **Use appropriate configuration:**
   ```elixir
   # Enable compression for Erlang terms
   ErlangTermSerializer.serialize(data)  # Uses :compressed by default
   
   # Configure JSON for better performance
   config :jason, :decode_options, keys: :atoms  # If safe
   ```

4. **Batch operations when possible:**
   ```elixir
   # More efficient than individual serialization
   Signal.serialize([signal1, signal2, signal3])
   ```

## Testing Serialization

### Test Custom Serializers

```elixir
defmodule MySerializerTest do
  use ExUnit.Case
  alias MyApp.CustomSerializer

  test "round-trip serialization preserves data" do
    original_data = %{key: "value", number: 42}
    
    {:ok, serialized} = CustomSerializer.serialize(original_data)
    assert is_binary(serialized)
    
    {:ok, deserialized} = CustomSerializer.deserialize(serialized)
    assert deserialized == original_data
  end

  test "handles serialization errors gracefully" do
    invalid_data = %{binary: <<0xFF, 0xFE>>}  # Invalid UTF-8
    
    assert {:error, _reason} = CustomSerializer.serialize(invalid_data)
  end

  test "validates input during deserialization" do
    invalid_binary = "not valid format"
    
    assert {:error, _reason} = CustomSerializer.deserialize(invalid_binary)
  end
end
```
