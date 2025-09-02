defmodule Jido.SignalSerializationTest do
  use ExUnit.Case, async: false

  alias Jido.Signal

  describe "Signal.serialize/1" do
    test "serializes a simple signal" do
      signal = %Signal{
        type: "test.event",
        source: "/test/source",
        id: "test-id-123"
      }

      {:ok, json} = Signal.serialize(signal)
      assert is_binary(json)

      decoded = Jason.decode!(json)
      assert decoded["type"] == "test.event"
      assert decoded["source"] == "/test/source"
      assert decoded["id"] == "test-id-123"
      assert decoded["specversion"] == "1.0.2"
    end

    test "serializes a signal with data" do
      signal = %Signal{
        type: "test.event",
        source: "/test/source",
        id: "test-id-123",
        data: %{key: "value", number: 42}
      }

      {:ok, json} = Signal.serialize(signal)
      assert is_binary(json)

      decoded = Jason.decode!(json)
      assert decoded["data"]["key"] == "value"
      assert decoded["data"]["number"] == 42
    end

    test "serializes a list of signals" do
      signals = [
        %Signal{type: "first.event", source: "/test/first", id: "first-id"},
        %Signal{type: "second.event", source: "/test/second", id: "second-id"}
      ]

      {:ok, json} = Signal.serialize(signals)
      assert is_binary(json)

      decoded = Jason.decode!(json)
      assert length(decoded) == 2
      assert Enum.at(decoded, 0)["type"] == "first.event"
      assert Enum.at(decoded, 1)["type"] == "second.event"
    end

    test "legacy serialize! function" do
      signal = %Signal{
        type: "test.event",
        source: "/test/source",
        id: "test-id-123"
      }

      json = Signal.serialize!(signal)
      assert is_binary(json)

      decoded = Jason.decode!(json)
      assert decoded["type"] == "test.event"
    end
  end

  describe "Signal.deserialize/1" do
    test "deserializes a simple signal" do
      json =
        ~s({"type":"test.event","source":"/test/source","id":"test-id-123","specversion":"1.0.2"})

      {:ok, signal} = Signal.deserialize(json)
      assert %Signal{} = signal
      assert signal.type == "test.event"
      assert signal.source == "/test/source"
      assert signal.id == "test-id-123"
      assert signal.specversion == "1.0.2"
    end

    test "deserializes a signal with data" do
      json =
        ~s({"type":"test.event","source":"/test/source","id":"test-id-123","specversion":"1.0.2","data":{"key":"value","number":42}})

      {:ok, signal} = Signal.deserialize(json)
      assert %Signal{} = signal
      assert signal.data["key"] == "value"
      assert signal.data["number"] == 42
    end

    test "deserializes a list of signals" do
      json = ~s([
        {"type":"first.event","source":"/test/first","id":"first-id","specversion":"1.0.2"},
        {"type":"second.event","source":"/test/second","id":"second-id","specversion":"1.0.2"}
      ])

      {:ok, signals} = Signal.deserialize(json)
      assert is_list(signals)
      assert length(signals) == 2

      first = Enum.at(signals, 0)
      second = Enum.at(signals, 1)

      assert first.type == "first.event"
      assert second.type == "second.event"
    end

    test "returns error for invalid JSON" do
      json = ~s({"type":"broken")

      result = Signal.deserialize(json)
      assert {:error, _reason} = result
    end

    test "returns error for invalid signal structure" do
      json = ~s({"not_a_type":"test.event"})

      result = Signal.deserialize(json)
      assert {:error, _reason} = result
    end
  end

  describe "round-trip serialization" do
    test "preserves signal data through serialization and deserialization" do
      original = %Signal{
        type: "test.event",
        source: "/test/source",
        id: "test-id-123",
        subject: "test-subject",
        time: "2023-01-01T12:00:00Z",
        datacontenttype: "application/json",
        dataschema: "https://example.com/schema",
        data: %{
          "string" => "value",
          "number" => 42,
          "boolean" => true,
          "nested" => %{"key" => "nested-value"}
        }
      }

      {:ok, json} = Signal.serialize(original)
      {:ok, deserialized} = Signal.deserialize(json)

      assert deserialized.type == original.type
      assert deserialized.source == original.source
      assert deserialized.id == original.id
      assert deserialized.subject == original.subject
      assert deserialized.time == original.time
      assert deserialized.datacontenttype == original.datacontenttype
      assert deserialized.dataschema == original.dataschema
      assert deserialized.data["string"] == original.data["string"]
      assert deserialized.data["number"] == original.data["number"]
      assert deserialized.data["boolean"] == original.data["boolean"]
      assert deserialized.data["nested"]["key"] == original.data["nested"]["key"]
    end

    test "preserves list of signals through serialization and deserialization" do
      originals = [
        %Signal{type: "first.event", source: "/test/first", id: "first-id"},
        %Signal{type: "second.event", source: "/test/second", id: "second-id"}
      ]

      {:ok, json} = Signal.serialize(originals)
      {:ok, deserialized} = Signal.deserialize(json)

      assert length(deserialized) == length(originals)

      Enum.zip(originals, deserialized)
      |> Enum.each(fn {original, deserialized} ->
        assert deserialized.type == original.type
        assert deserialized.source == original.source
        assert deserialized.id == original.id
      end)
    end

    test "round-trip with different serializers" do
      signal = %Signal{
        type: "test.event",
        source: "/test/source",
        id: "test-id-123",
        data: %{"message" => "hello", "count" => 42}
      }

      serializers = [
        Jido.Signal.Serialization.JsonSerializer,
        Jido.Signal.Serialization.ErlangTermSerializer,
        Jido.Signal.Serialization.MsgpackSerializer
      ]

      for serializer <- serializers do
        {:ok, binary} = Signal.serialize(signal, serializer: serializer)
        {:ok, deserialized} = Signal.deserialize(binary, serializer: serializer)

        assert deserialized.type == signal.type
        assert deserialized.source == signal.source
        assert deserialized.id == signal.id
      end
    end
  end

  describe "extension serialization" do
    # Define test extensions for serialization testing
    defmodule SimpleTestExt do
      use Jido.Signal.Ext,
        namespace: "simpletest",
        schema: [
          message: [type: :string, required: true]
        ]
    end

    defmodule ComplexTestExt do
      use Jido.Signal.Ext,
        namespace: "complextest",
        schema: [
          complex_user_id: [type: :string, required: true],
          complex_roles: [type: {:list, :string}, default: []],
          count: [type: :non_neg_integer, default: 0]
        ]
    end

    defmodule CustomSerializationTestExt do
      use Jido.Signal.Ext,
        namespace: "customtest",
        schema: [
          data: [type: :string, required: true],
          prefix: [type: :string, default: "test"]
        ]

      @impl Jido.Signal.Ext
      def to_attrs(%{data: data, prefix: prefix}) do
        %{"custom_data" => "#{prefix}_#{data}"}
      end

      @impl Jido.Signal.Ext
      def from_attrs(attrs) do
        case Map.get(attrs, "custom_data") do
          nil ->
            nil

          custom_data ->
            case String.split(custom_data, "_", parts: 2) do
              [prefix, data] -> %{data: data, prefix: prefix}
              [data] -> %{data: data, prefix: "test"}
            end
        end
      end
    end

    setup do
      # Create a base signal for testing
      signal = %Signal{
        type: "test.event",
        source: "/test/source",
        id: "test-id-123",
        data: %{message: "hello world"}
      }

      %{signal: signal}
    end

    test "serializes signal with simple extension", %{signal: signal} do
      # Add simple extension
      {:ok, extended_signal} = Signal.put_extension(signal, "simpletest", %{message: "test"})

      {:ok, json} = Signal.serialize(extended_signal)
      assert is_binary(json)

      decoded = Jason.decode!(json)

      # Should contain extension data as top-level attributes
      assert decoded["message"] == "test"

      # Should contain core CloudEvents fields
      assert decoded["type"] == "test.event"
      assert decoded["source"] == "/test/source"
      assert decoded["id"] == "test-id-123"
      assert decoded["data"]["message"] == "hello world"

      # Should NOT contain extensions field in serialized JSON
      refute Map.has_key?(decoded, "extensions")
    end

    test "serializes signal with complex extension", %{signal: signal} do
      # Add complex extension with defaults
      {:ok, extended_signal} =
        Signal.put_extension(signal, "complextest", %{
          complex_user_id: "user123",
          complex_roles: ["admin", "user"]
        })

      {:ok, json} = Signal.serialize(extended_signal)
      decoded = Jason.decode!(json)

      # Should contain extension data as top-level attributes
      assert decoded["complex_user_id"] == "user123"
      assert decoded["complex_roles"] == ["admin", "user"]
      # default value
      assert decoded["count"] == 0

      # Should contain core fields
      assert decoded["type"] == "test.event"
      refute Map.has_key?(decoded, "extensions")
    end

    test "serializes signal with custom serialization extension", %{signal: signal} do
      # Add extension with custom serialization
      {:ok, extended_signal} =
        Signal.put_extension(signal, "customtest", %{
          data: "mydata",
          prefix: "custom"
        })

      {:ok, json} = Signal.serialize(extended_signal)
      decoded = Jason.decode!(json)

      # Should use custom serialization
      assert decoded["custom_data"] == "custom_mydata"

      # Should still have Signal.data field (core CloudEvents field)
      assert decoded["data"]["message"] == "hello world"

      # Should NOT have the original extension fields as separate keys
      refute Map.has_key?(decoded, "prefix")
      refute Map.has_key?(decoded, "extensions")
    end

    test "serializes signal with multiple extensions", %{signal: signal} do
      # Add multiple extensions
      {:ok, signal1} = Signal.put_extension(signal, "simpletest", %{message: "simple"})
      {:ok, signal2} = Signal.put_extension(signal1, "complextest", %{complex_user_id: "user456"})

      {:ok, json} = Signal.serialize(signal2)
      decoded = Jason.decode!(json)

      # Should contain data from both extensions
      assert decoded["message"] == "simple"
      assert decoded["complex_user_id"] == "user456"
      # default
      assert decoded["complex_roles"] == []
      # default
      assert decoded["count"] == 0

      # Core fields should still be present
      assert decoded["type"] == "test.event"
      refute Map.has_key?(decoded, "extensions")
    end

    test "deserializes signal with simple extension", %{signal: _signal} do
      # Create JSON with extension data as top-level attributes
      json =
        Jason.encode!(%{
          "type" => "test.event",
          "source" => "/test/source",
          "id" => "test-id-123",
          "specversion" => "1.0.2",
          "data" => %{"message" => "hello world"},
          # extension data
          "message" => "deserialized test"
        })

      {:ok, deserialized} = Signal.deserialize(json)

      assert %Signal{} = deserialized
      assert deserialized.type == "test.event"
      assert deserialized.data["message"] == "hello world"

      # Extension should be inflated back
      extension_data = Signal.get_extension(deserialized, "simpletest")
      assert extension_data != nil
      assert extension_data.message == "deserialized test"
    end

    test "deserializes signal with complex extension" do
      json =
        Jason.encode!(%{
          "type" => "complex.event",
          "source" => "/complex/source",
          "id" => "complex-123",
          "specversion" => "1.0.2",
          "complex_user_id" => "complex_user",
          "complex_roles" => ["viewer", "editor"],
          "count" => 42
        })

      {:ok, deserialized} = Signal.deserialize(json)

      # Extension should be properly reconstructed
      extension_data = Signal.get_extension(deserialized, "complextest")
      assert extension_data != nil
      assert extension_data.complex_user_id == "complex_user"
      assert extension_data.complex_roles == ["viewer", "editor"]
      assert extension_data.count == 42
    end

    test "deserializes signal with custom serialization extension" do
      json =
        Jason.encode!(%{
          "type" => "custom.event",
          "source" => "/custom/source",
          "id" => "custom-123",
          "specversion" => "1.0.2",
          "custom_data" => "myprefix_myvalue"
        })

      {:ok, deserialized} = Signal.deserialize(json)

      # Custom deserialization should work
      extension_data = Signal.get_extension(deserialized, "customtest")
      assert extension_data != nil
      assert extension_data.data == "myvalue"
      assert extension_data.prefix == "myprefix"
    end

    test "round-trip serialization preserves extension data", %{signal: signal} do
      # Create signal with multiple extensions
      {:ok, signal1} = Signal.put_extension(signal, "simpletest", %{message: "round-trip"})

      {:ok, signal2} =
        Signal.put_extension(signal1, "complextest", %{
          complex_user_id: "roundtrip123",
          complex_roles: ["test", "round", "trip"],
          count: 99
        })

      # Serialize and deserialize
      {:ok, json} = Signal.serialize(signal2)
      {:ok, deserialized} = Signal.deserialize(json)

      # Verify core Signal fields
      assert deserialized.type == signal2.type
      assert deserialized.source == signal2.source
      assert deserialized.id == signal2.id
      # Data might have string keys after deserialization instead of atom keys
      assert deserialized.data["message"] == signal2.data.message

      # Verify extension data
      simple_ext = Signal.get_extension(deserialized, "simpletest")
      assert simple_ext.message == "round-trip"

      complex_ext = Signal.get_extension(deserialized, "complextest")
      assert complex_ext.complex_user_id == "roundtrip123"
      assert complex_ext.complex_roles == ["test", "round", "trip"]
      assert complex_ext.count == 99
    end

    test "round-trip with different serializers preserves extensions", %{signal: signal} do
      {:ok, extended_signal} =
        Signal.put_extension(signal, "simpletest", %{message: "serializer_test"})

      serializers = [
        Jido.Signal.Serialization.JsonSerializer,
        Jido.Signal.Serialization.ErlangTermSerializer,
        Jido.Signal.Serialization.MsgpackSerializer
      ]

      for serializer <- serializers do
        {:ok, binary} = Signal.serialize(extended_signal, serializer: serializer)
        {:ok, deserialized} = Signal.deserialize(binary, serializer: serializer)

        assert deserialized.type == extended_signal.type
        extension_data = Signal.get_extension(deserialized, "simpletest")
        assert extension_data != nil
        assert extension_data.message == "serializer_test"
      end
    end

    test "deserialization without extensions works (backward compatibility)" do
      # JSON without any extension data
      json =
        Jason.encode!(%{
          "type" => "simple.event",
          "source" => "/simple/source",
          "id" => "simple-123",
          "specversion" => "1.0.2",
          "data" => %{"key" => "value"}
        })

      {:ok, deserialized} = Signal.deserialize(json)

      assert %Signal{} = deserialized
      assert deserialized.type == "simple.event"
      assert deserialized.data["key"] == "value"
      # empty extensions
      assert deserialized.extensions == %{}
    end

    test "serialized format is CloudEvents compliant" do
      {:ok, extended_signal} =
        Signal.put_extension(
          %Signal{
            type: "cloudevents.test",
            source: "/cloudevents",
            id: "ce-123",
            subject: "test-subject",
            time: "2023-01-01T12:00:00Z",
            datacontenttype: "application/json",
            data: %{test: "data"}
          },
          "simpletest",
          %{message: "cloudevents"}
        )

      {:ok, json} = Signal.serialize(extended_signal)
      decoded = Jason.decode!(json)

      # Required CloudEvents fields
      assert decoded["specversion"] == "1.0.2"
      assert decoded["type"] == "cloudevents.test"
      assert decoded["source"] == "/cloudevents"
      assert decoded["id"] == "ce-123"

      # Optional CloudEvents fields
      assert decoded["subject"] == "test-subject"
      assert decoded["time"] == "2023-01-01T12:00:00Z"
      assert decoded["datacontenttype"] == "application/json"
      assert decoded["data"]["test"] == "data"

      # Extension appears as top-level attribute
      assert decoded["message"] == "cloudevents"

      # No Jido-specific fields in serialized form (extensions should be flattened)
      refute Map.has_key?(decoded, "extensions")
      # jido_dispatch should not appear since it's nil (filtered out by flatten_extensions)
      refute Map.has_key?(decoded, "jido_dispatch")
    end

    test "handles unknown extension attributes during deserialization" do
      # JSON with attributes that don't match any registered extension
      json =
        Jason.encode!(%{
          "type" => "unknown.test",
          "source" => "/unknown",
          "id" => "unknown-123",
          "specversion" => "1.0.2",
          "unknown_field" => "unknown_value",
          "another_unknown" => 42
        })

      {:ok, deserialized} = Signal.deserialize(json)

      # Should deserialize successfully
      assert %Signal{} = deserialized
      assert deserialized.type == "unknown.test"

      # Unknown fields should be ignored (not cause errors)
      assert deserialized.extensions == %{}
    end

    test "extension attributes don't interfere with core CloudEvents fields" do
      # Test potential conflicts
      {:ok, signal_with_time_ext} =
        Signal.put_extension(
          %Signal{
            type: "conflict.test",
            source: "/conflict",
            id: "conflict-123",
            # Core CloudEvents time
            time: "2023-01-01T12:00:00Z"
          },
          "simpletest",
          %{message: "no conflict"}
        )

      {:ok, json} = Signal.serialize(signal_with_time_ext)
      {:ok, deserialized} = Signal.deserialize(json)

      # Core time field should be preserved
      assert deserialized.time == "2023-01-01T12:00:00Z"

      # Extension should also be preserved
      extension_data = Signal.get_extension(deserialized, "simpletest")
      assert extension_data.message == "no conflict"
    end
  end
end
