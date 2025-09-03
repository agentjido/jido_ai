defmodule JidoTest.SignalTest do
  use ExUnit.Case, async: true

  alias Jido.Signal

  # Simple test extension for testing extension API
  defmodule TestExtension do
    use Jido.Signal.Ext,
      namespace: "testext",
      schema: [
        user_id: [type: :string, required: true],
        count: [type: :non_neg_integer, default: 0],
        enabled: [type: :boolean, default: true]
      ]
  end

  describe "new/1" do
    test "creates a signal with default id and source" do
      {:ok, signal} = Signal.new(%{type: "example.event"})

      assert is_binary(signal.id)
      # UUID length
      assert String.length(signal.id) == 36
      assert signal.source == "Elixir.JidoTest.SignalTest"
      assert signal.type == "example.event"
    end

    test "allows overriding default id and source" do
      {:ok, signal} =
        Signal.new(%{
          id: "custom-id",
          source: "custom-source",
          type: "example.event"
        })

      assert signal.id == "custom-id"
      assert signal.source == "custom-source"
    end

    test "sets specversion and time defaults" do
      {:ok, signal} = Signal.new(%{type: "example.event"})

      assert signal.specversion == "1.0.2"
      assert is_binary(signal.time)
      # ISO8601 format
      assert String.contains?(signal.time, "T")
    end
  end

  describe "from_map/1" do
    test "creates a valid Signal struct with required fields" do
      map = %{
        "specversion" => "1.0.2",
        "type" => "example.event",
        "source" => "/example",
        "id" => "123"
      }

      assert {:ok, signal} = Signal.from_map(map)
      assert %Signal{} = signal
      assert signal.specversion == "1.0.2"
      assert signal.type == "example.event"
      assert signal.source == "/example"
      assert signal.id == "123"
    end

    test "creates a valid Signal struct with all fields" do
      map = %{
        "specversion" => "1.0.2",
        "type" => "example.event",
        "source" => "/example",
        "id" => "123",
        "subject" => "test_subject",
        "time" => "2023-05-20T12:00:00Z",
        "datacontenttype" => "application/json",
        "dataschema" => "https://example.com/schema",
        "data" => %{"key" => "value"}
      }

      assert {:ok, signal} = Signal.from_map(map)
      assert %Signal{} = signal
      assert signal.subject == "test_subject"
      assert signal.time == "2023-05-20T12:00:00Z"
      assert signal.datacontenttype == "application/json"
      assert signal.dataschema == "https://example.com/schema"
      assert signal.data == %{"key" => "value"}
    end

    test "returns error for invalid specversion" do
      map = %{
        "specversion" => "1.0",
        "type" => "example.event",
        "source" => "/example",
        "id" => "123"
      }

      assert {:error, "parse error: unexpected specversion 1.0"} = Signal.from_map(map)
    end

    test "returns error for missing required fields" do
      map = %{"specversion" => "1.0.2"}
      assert {:error, "parse error: missing type"} = Signal.from_map(map)
    end

    test "handles empty optional fields" do
      map = %{
        "specversion" => "1.0.2",
        "type" => "example.event",
        "source" => "/example",
        "id" => "123",
        "subject" => "",
        "time" => "",
        "datacontenttype" => "",
        "dataschema" => ""
      }

      assert {:error, _} = Signal.from_map(map)
    end

    test "sets default datacontenttype for non-nil data" do
      map = %{
        "specversion" => "1.0.2",
        "type" => "example.event",
        "source" => "/example",
        "id" => "123",
        "data" => %{"key" => "value"}
      }

      assert {:ok, signal} = Signal.from_map(map)
      assert signal.datacontenttype == "application/json"
    end
  end

  describe "new/3 and new!/3" do
    test "creates signal with positional type and data" do
      {:ok, signal} = Signal.new("user.created", %{user_id: "123"})

      assert signal.type == "user.created"
      assert signal.data == %{user_id: "123"}
      assert signal.specversion == "1.0.2"
      assert is_binary(signal.id)
      assert is_binary(signal.source)
      assert is_binary(signal.time)
    end

    test "accepts keyword list for attrs" do
      {:ok, signal} =
        Signal.new("user.created", %{user_id: "123"},
          source: "/auth/registration",
          subject: "welcome-email"
        )

      assert signal.type == "user.created"
      assert signal.data == %{user_id: "123"}
      assert signal.source == "/auth/registration"
      assert signal.subject == "welcome-email"
    end

    test "accepts map for attrs" do
      {:ok, signal} =
        Signal.new("order.placed", %{order_id: 456}, %{source: "/orders", subject: "new-order"})

      assert signal.type == "order.placed"
      assert signal.data == %{order_id: 456}
      assert signal.source == "/orders"
      assert signal.subject == "new-order"
    end

    test "works with empty attrs" do
      {:ok, signal} = Signal.new("test.event", %{ok?: true})

      assert signal.type == "test.event"
      assert signal.data == %{ok?: true}
    end

    test "works with empty attrs map" do
      {:ok, signal} = Signal.new("test.event", %{ok?: true}, %{})

      assert signal.type == "test.event"
      assert signal.data == %{ok?: true}
    end

    test "rejects reserved keys in attrs" do
      assert {:error, error} = Signal.new("test.event", %{}, type: "override")
      assert error =~ "attribute :type must not be passed in attrs"

      assert {:error, error} = Signal.new("test.event", %{}, %{"type" => "override"})
      assert error =~ "attribute \"type\" must not be passed in attrs"

      assert {:error, error} = Signal.new("test.event", %{}, data: %{bad: true})
      assert error =~ "attribute :data must not be passed in attrs"

      assert {:error, error} = Signal.new("test.event", %{}, %{"data" => %{bad: true}})
      assert error =~ "attribute \"data\" must not be passed in attrs"
    end

    test "validates type parameter" do
      assert {:error, error} = Signal.new(123, %{})
      assert error =~ "expected new/3"

      assert {:error, error} = Signal.new(nil, %{})
      assert error =~ "expected new/3"
    end

    test "validates attrs parameter" do
      assert {:error, error} = Signal.new("test.event", %{}, "not a map or list")
      assert error =~ "expected new/3"

      assert {:error, error} = Signal.new("test.event", %{}, 123)
      assert error =~ "expected new/3"
    end

    test "new!/3 returns signal on success" do
      signal = Signal.new!("user.created", %{user_id: "123"}, source: "/auth")

      assert signal.type == "user.created"
      assert signal.data == %{user_id: "123"}
      assert signal.source == "/auth"
    end

    test "new!/3 raises on error" do
      assert_raise ArgumentError, ~r/invalid signal/, fn ->
        Signal.new!("test.event", %{}, type: "forbidden")
      end
    end

    test "accepts various data types" do
      # String data
      {:ok, signal} = Signal.new("log.message", "Hello world")
      assert signal.data == "Hello world"

      # List data
      {:ok, signal} = Signal.new("batch.items", [1, 2, 3])
      assert signal.data == [1, 2, 3]

      # Nil data
      {:ok, signal} = Signal.new("heartbeat", nil)
      assert signal.data == nil

      # Complex nested data
      complex_data = %{user: %{id: 1, profile: %{name: "John"}}, items: [1, 2]}
      {:ok, signal} = Signal.new("complex.event", complex_data)
      assert signal.data == complex_data
    end

    test "new!/1 raises on error" do
      assert_raise RuntimeError, fn ->
        # missing required type
        Signal.new!(%{source: "/test"})
      end
    end
  end

  describe "extension API" do
    setup do
      {:ok, signal} = Signal.new("test.event", %{message: "hello"})
      {:ok, signal: signal}
    end

    test "put_extension/3 validates and stores extension data", %{signal: signal} do
      # Valid extension data
      {:ok, updated_signal} = Signal.put_extension(signal, "testext", %{user_id: "123"})

      assert updated_signal.extensions["testext"] == %{user_id: "123", count: 0, enabled: true}
      assert updated_signal.type == signal.type
      assert updated_signal.data == signal.data
    end

    test "put_extension/3 returns error for invalid data", %{signal: signal} do
      # Missing required field
      {:error, reason} = Signal.put_extension(signal, "testext", %{count: 5})
      assert reason =~ "user_id"

      # Invalid type
      {:error, reason} = Signal.put_extension(signal, "testext", %{user_id: 123})
      assert reason =~ "user_id"
    end

    test "put_extension/3 returns error for unknown extension", %{signal: signal} do
      {:error, reason} = Signal.put_extension(signal, "unknown", %{data: "test"})
      assert reason == "Unknown extension: unknown"
    end

    test "put_extension/3 validates input parameters" do
      {:error, reason} = Signal.put_extension("not a signal", "testext", %{})
      assert reason == "Expected Signal struct, namespace string, and extension data"

      {:ok, signal} = Signal.new("test.event", %{})
      {:error, reason} = Signal.put_extension(signal, 123, %{})
      assert reason == "Expected Signal struct, namespace string, and extension data"
    end

    test "get_extension/2 retrieves extension data", %{signal: signal} do
      # No extension data initially
      assert Signal.get_extension(signal, "testext") == nil

      # Add extension data
      {:ok, updated_signal} =
        Signal.put_extension(signal, "testext", %{user_id: "456", count: 10})

      # Retrieve extension data
      ext_data = Signal.get_extension(updated_signal, "testext")
      assert ext_data == %{user_id: "456", count: 10, enabled: true}
    end

    test "get_extension/2 returns nil for unknown extensions", %{signal: signal} do
      assert Signal.get_extension(signal, "unknown") == nil
    end

    test "get_extension/2 handles invalid parameters" do
      assert Signal.get_extension("not a signal", "testext") == nil
      assert Signal.get_extension(%{}, "testext") == nil

      {:ok, signal} = Signal.new("test.event", %{})
      assert Signal.get_extension(signal, 123) == nil
    end

    test "delete_extension/2 removes extension data", %{signal: signal} do
      # Add extension data
      {:ok, updated_signal} = Signal.put_extension(signal, "testext", %{user_id: "789"})
      assert Signal.get_extension(updated_signal, "testext") != nil

      # Remove extension data
      final_signal = Signal.delete_extension(updated_signal, "testext")
      assert Signal.get_extension(final_signal, "testext") == nil
      assert final_signal.extensions == %{}
    end

    test "delete_extension/2 handles non-existent extensions", %{signal: signal} do
      # Should not error when removing non-existent extension
      updated_signal = Signal.delete_extension(signal, "nonexistent")
      assert updated_signal == signal
    end

    test "delete_extension/2 handles invalid parameters" do
      result = Signal.delete_extension("not a signal", "testext")
      assert result == "not a signal"

      {:ok, signal} = Signal.new("test.event", %{})
      result = Signal.delete_extension(signal, 123)
      assert result == signal
    end

    test "list_extensions/1 returns extension namespaces", %{signal: signal} do
      # No extensions initially
      assert Signal.list_extensions(signal) == []

      # Add one extension
      {:ok, signal1} = Signal.put_extension(signal, "testext", %{user_id: "123"})
      assert Signal.list_extensions(signal1) == ["testext"]
    end

    test "list_extensions/1 handles invalid parameters" do
      assert Signal.list_extensions("not a signal") == []
      assert Signal.list_extensions(%{}) == []
      assert Signal.list_extensions(nil) == []
    end

    test "extensions don't interfere with existing functionality", %{signal: signal} do
      # Add extension
      {:ok, extended_signal} = Signal.put_extension(signal, "testext", %{user_id: "123"})

      # Core Signal functionality should work normally
      assert extended_signal.type == signal.type
      assert extended_signal.data == signal.data
      assert extended_signal.id == signal.id
      assert extended_signal.source == signal.source
      assert extended_signal.specversion == signal.specversion

      # Serialization should still work (extensions excluded from JSON)
      {:ok, json} = Signal.serialize(extended_signal)
      assert is_binary(json)

      # Should not contain extension data in serialized JSON
      refute String.contains?(json, "testext")
    end

    test "multiple extensions work together", %{signal: signal} do
      # Create a second test extension
      defmodule TestExtension2 do
        use Jido.Signal.Ext,
          namespace: "testext2",
          schema: [
            session_id: [type: :string, required: true],
            timestamp: [type: :non_neg_integer, default: 0]
          ]
      end

      # Add multiple extensions
      {:ok, signal1} = Signal.put_extension(signal, "testext", %{user_id: "123"})
      {:ok, signal2} = Signal.put_extension(signal1, "testext2", %{session_id: "abc"})

      # Both extensions should be present
      assert Signal.get_extension(signal2, "testext") == %{
               user_id: "123",
               count: 0,
               enabled: true
             }

      assert Signal.get_extension(signal2, "testext2") == %{session_id: "abc", timestamp: 0}

      # List should contain both
      extensions = Signal.list_extensions(signal2) |> Enum.sort()
      assert extensions == ["testext", "testext2"]

      # Remove one extension
      signal3 = Signal.delete_extension(signal2, "testext")
      assert Signal.get_extension(signal3, "testext") == nil
      assert Signal.get_extension(signal3, "testext2") == %{session_id: "abc", timestamp: 0}
      assert Signal.list_extensions(signal3) == ["testext2"]
    end
  end
end
