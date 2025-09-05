defmodule Jido.Signal.Ext.TraceTest do
  use ExUnit.Case, async: true

  alias Jido.Signal.Ext.Trace

  setup do
    # Ensure the extension is registered
    Jido.Signal.Ext.Registry.register(Trace)
    :ok
  end

  describe "schema validation" do
    test "accepts valid data with required fields" do
      data = %{
        trace_id: "trace-123",
        span_id: "span-456"
      }

      assert {:ok, _} = Trace.validate_data(data)
    end

    test "accepts optional parent_span_id and causation_id" do
      data = %{
        trace_id: "trace-123",
        span_id: "span-456",
        parent_span_id: "parent-789",
        causation_id: "signal-abc"
      }

      assert {:ok, _} = Trace.validate_data(data)
    end

    test "requires trace_id" do
      data = %{span_id: "span-456"}
      assert {:error, _} = Trace.validate_data(data)
    end

    test "requires span_id" do
      data = %{trace_id: "trace-123"}
      assert {:error, _} = Trace.validate_data(data)
    end
  end

  describe "CloudEvents serialization" do
    test "serializes minimal data to CloudEvents attributes" do
      data = %{
        trace_id: "trace-123",
        span_id: "span-456"
      }

      attrs = Trace.to_attrs(data)

      assert %{
               "trace_id" => "trace-123",
               "span_id" => "span-456"
             } = attrs

      refute Map.has_key?(attrs, "parent_span_id")
      refute Map.has_key?(attrs, "causation_id")
    end

    test "serializes full data to CloudEvents attributes" do
      data = %{
        trace_id: "trace-123",
        span_id: "span-456",
        parent_span_id: "parent-789",
        causation_id: "signal-abc"
      }

      attrs = Trace.to_attrs(data)

      assert %{
               "trace_id" => "trace-123",
               "span_id" => "span-456",
               "parent_span_id" => "parent-789",
               "causation_id" => "signal-abc"
             } = attrs
    end

    test "omits nil optional fields" do
      data = %{
        trace_id: "trace-123",
        span_id: "span-456",
        parent_span_id: nil,
        causation_id: "signal-abc"
      }

      attrs = Trace.to_attrs(data)

      assert %{
               "trace_id" => "trace-123",
               "span_id" => "span-456",
               "causation_id" => "signal-abc"
             } = attrs

      refute Map.has_key?(attrs, "parent_span_id")
    end
  end

  describe "CloudEvents deserialization" do
    test "deserializes minimal CloudEvents attributes" do
      attrs = %{
        "trace_id" => "trace-123",
        "span_id" => "span-456"
      }

      data = Trace.from_attrs(attrs)

      assert %{
               trace_id: "trace-123",
               span_id: "span-456",
               parent_span_id: nil,
               causation_id: nil
             } = data
    end

    test "deserializes full CloudEvents attributes" do
      attrs = %{
        "trace_id" => "trace-123",
        "span_id" => "span-456",
        "parent_span_id" => "parent-789",
        "causation_id" => "signal-abc"
      }

      data = Trace.from_attrs(attrs)

      assert %{
               trace_id: "trace-123",
               span_id: "span-456",
               parent_span_id: "parent-789",
               causation_id: "signal-abc"
             } = data
    end

    test "returns nil when no trace_id present" do
      attrs = %{
        "span_id" => "span-456",
        "other" => "data"
      }

      assert nil == Trace.from_attrs(attrs)
    end

    test "handles missing optional attributes" do
      attrs = %{
        "trace_id" => "trace-123",
        "span_id" => "span-456"
        # missing parent_span_id and causation_id
      }

      data = Trace.from_attrs(attrs)

      assert %{
               trace_id: "trace-123",
               span_id: "span-456",
               parent_span_id: nil,
               causation_id: nil
             } = data
    end
  end

  describe "round-trip serialization" do
    test "preserves minimal data through serialization round-trip" do
      original = %{
        trace_id: "trace-123",
        span_id: "span-456"
      }

      attrs = Trace.to_attrs(original)
      restored = Trace.from_attrs(attrs)

      assert original.trace_id == restored.trace_id
      assert original.span_id == restored.span_id
      assert restored.parent_span_id == nil
      assert restored.causation_id == nil
    end

    test "preserves full data through serialization round-trip" do
      original = %{
        trace_id: "trace-123",
        span_id: "span-456",
        parent_span_id: "parent-789",
        causation_id: "signal-abc"
      }

      attrs = Trace.to_attrs(original)
      restored = Trace.from_attrs(attrs)

      assert original == restored
    end

    test "handles partial data correctly" do
      original = %{
        trace_id: "trace-123",
        span_id: "span-456",
        parent_span_id: "parent-789",
        causation_id: nil
      }

      attrs = Trace.to_attrs(original)
      restored = Trace.from_attrs(attrs)

      assert original.trace_id == restored.trace_id
      assert original.span_id == restored.span_id
      assert original.parent_span_id == restored.parent_span_id
      assert restored.causation_id == nil
    end
  end

  describe "integration with Jido.Signal" do
    test "can be added to and retrieved from a Signal" do
      trace_data = %{
        trace_id: "trace-123",
        span_id: "span-456",
        parent_span_id: "parent-789",
        causation_id: "signal-abc"
      }

      {:ok, signal} = Jido.Signal.new("test.event", %{test: "data"})
      {:ok, signal_with_trace} = Jido.Signal.put_extension(signal, "correlation", trace_data)

      retrieved_data = Jido.Signal.get_extension(signal_with_trace, "correlation")
      assert trace_data == retrieved_data
    end

    test "survives Signal serialization round-trip" do
      trace_data = %{
        trace_id: "trace-123",
        span_id: "span-456",
        parent_span_id: "parent-789",
        causation_id: "signal-abc"
      }

      {:ok, signal} = Jido.Signal.new("test.event", %{test: "data"})
      {:ok, signal_with_trace} = Jido.Signal.put_extension(signal, "correlation", trace_data)

      # Serialize and deserialize
      {:ok, json} = Jido.Signal.serialize(signal_with_trace)
      {:ok, restored_signal} = Jido.Signal.deserialize(json)

      # Trace data should be preserved
      retrieved_data = Jido.Signal.get_extension(restored_signal, "correlation")
      assert trace_data == retrieved_data
    end
  end
end
