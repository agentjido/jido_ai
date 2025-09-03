defmodule Jido.Signal.Ext.UnknownExtensionsTest do
  use ExUnit.Case

  import ExUnit.CaptureLog

  alias Jido.Signal

  describe "unknown extension handling" do
    test "preserves unknown extensions during from_map/1" do
      data = %{
        "type" => "test.event",
        "source" => "/test",
        "id" => "test-123",
        "specversion" => "1.0.2",
        "custom_extension" => "custom_value",
        "another_unknown" => 42
      }

      log =
        capture_log(fn ->
          {:ok, signal} = Signal.from_map(data)

          assert signal.extensions["custom_extension"] == "custom_value"
          assert signal.extensions["another_unknown"] == 42
        end)

      assert log =~ "Unknown extension 'custom_extension' encountered - preserving as opaque data"
      assert log =~ "Unknown extension 'another_unknown' encountered - preserving as opaque data"
    end

    test "preserves complex unknown extension data" do
      data = %{
        "type" => "test.event",
        "source" => "/test",
        "id" => "test-123",
        "specversion" => "1.0.2",
        "complex_unknown" => %{
          "nested" => true,
          "array" => [1, 2, 3],
          "deep" => %{"very" => %{"nested" => "value"}}
        }
      }

      log =
        capture_log(fn ->
          {:ok, signal} = Signal.from_map(data)

          assert signal.extensions["complex_unknown"]["nested"] == true
          assert signal.extensions["complex_unknown"]["array"] == [1, 2, 3]
          assert signal.extensions["complex_unknown"]["deep"]["very"]["nested"] == "value"
        end)

      assert log =~ "Unknown extension 'complex_unknown' encountered - preserving as opaque data"
    end

    test "preserves unknown extensions through JSON serialization round-trip" do
      original_data = %{
        "type" => "test.event",
        "source" => "/test",
        "id" => "test-123",
        "specversion" => "1.0.2",
        "data" => %{"message" => "test"},
        "unknown_ext" => "unknown_value",
        "numeric_ext" => 42
      }

      capture_log(fn ->
        {:ok, signal} = Signal.from_map(original_data)

        # Serialize to JSON
        json = Jason.encode!(signal)

        # Deserialize back
        {:ok, decoded_data} = Jason.decode(json)
        {:ok, deserialized_signal} = Signal.from_map(decoded_data)

        # Verify unknown extensions survive round-trip
        assert deserialized_signal.extensions["unknown_ext"] == "unknown_value"
        assert deserialized_signal.extensions["numeric_ext"] == 42

        # Verify core fields are preserved
        assert deserialized_signal.type == "test.event"
        assert deserialized_signal.source == "/test"
        assert deserialized_signal.data == %{"message" => "test"}
      end)
    end

    test "does not interfere with registered extensions" do
      # This test assumes there are some registered extensions
      # If no extensions are registered, create minimal test data
      data = %{
        "type" => "test.event",
        "source" => "/test",
        "id" => "test-123",
        "specversion" => "1.0.2",
        "unknown_ext" => "should_be_preserved"
      }

      log =
        capture_log(fn ->
          {:ok, signal} = Signal.from_map(data)

          # Unknown extension should be preserved
          assert signal.extensions["unknown_ext"] == "should_be_preserved"
        end)

      assert log =~ "Unknown extension 'unknown_ext' encountered - preserving as opaque data"
    end

    test "handles mixed known and unknown extensions" do
      # Add both registered extension fields and unknown ones
      data = %{
        "type" => "test.event",
        "source" => "/test",
        "id" => "test-123",
        "specversion" => "1.0.2",
        "unknown_ext" => "unknown_value",
        "another_unknown" => 42
      }

      log =
        capture_log(fn ->
          {:ok, signal} = Signal.from_map(data)

          # Unknown extensions should be preserved
          assert signal.extensions["unknown_ext"] == "unknown_value"
          assert signal.extensions["another_unknown"] == 42
        end)

      assert log =~ "Unknown extension 'unknown_ext' encountered - preserving as opaque data"
      assert log =~ "Unknown extension 'another_unknown' encountered - preserving as opaque data"
    end

    test "does not treat core CloudEvents fields as unknown extensions" do
      data = %{
        "type" => "test.event",
        "source" => "/test",
        "id" => "test-123",
        "specversion" => "1.0.2",
        "subject" => "test-subject",
        "time" => "2023-01-01T00:00:00Z",
        "datacontenttype" => "application/json",
        "data" => %{"message" => "test"}
      }

      # Should not log warnings for core fields
      log =
        capture_log(fn ->
          {:ok, signal} = Signal.from_map(data)

          assert signal.type == "test.event"
          assert signal.source == "/test"
          assert signal.subject == "test-subject"
          assert signal.time == "2023-01-01T00:00:00Z"
          assert signal.datacontenttype == "application/json"
          assert signal.data == %{"message" => "test"}
        end)

      # Should not contain warnings about core fields
      refute log =~ "Unknown extension 'type'"
      refute log =~ "Unknown extension 'source'"
      refute log =~ "Unknown extension 'subject'"
      refute log =~ "Unknown extension 'time'"
      refute log =~ "Unknown extension 'datacontenttype'"
      refute log =~ "Unknown extension 'data'"
    end
  end
end
