defmodule JidoTest.SignalTest do
  use ExUnit.Case, async: true

  alias Jido.Signal

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
end
