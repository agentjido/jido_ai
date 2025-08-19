defmodule JidoTest.Signal.Dispatch.ConsoleAdapterTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  alias Jido.Signal
  alias Jido.Signal.Dispatch.ConsoleAdapter

  @moduletag :capture_log

  describe "behaviour implementation" do
    test "implements Adapter behaviour" do
      assert function_exported?(ConsoleAdapter, :validate_opts, 1)
      assert function_exported?(ConsoleAdapter, :deliver, 2)

      behaviours = ConsoleAdapter.__info__(:attributes)[:behaviour] || []
      assert Jido.Signal.Dispatch.Adapter in behaviours
    end
  end

  describe "validate_opts/1" do
    test "accepts empty options" do
      assert {:ok, []} = ConsoleAdapter.validate_opts([])
    end

    test "accepts any options and returns them unchanged" do
      opts = [timeout: 5000, format: :json, custom_option: "value"]
      assert {:ok, ^opts} = ConsoleAdapter.validate_opts(opts)
    end

    test "accepts non-keyword list options" do
      assert {:ok, %{any: "map"}} = ConsoleAdapter.validate_opts(%{any: "map"})
      assert {:ok, "string"} = ConsoleAdapter.validate_opts("string")
    end

    test "always returns :ok tuple" do
      test_cases = [
        [],
        [option: "value"],
        %{map: "option"},
        "string",
        123,
        nil
      ]

      for opts <- test_cases do
        assert {:ok, ^opts} = ConsoleAdapter.validate_opts(opts)
      end
    end
  end

  describe "deliver/2" do
    setup do
      {:ok, signal} =
        Signal.new(%{
          type: "test.signal",
          source: "/test/source",
          data: %{message: "test message", value: 42}
        })

      {:ok, signal: signal}
    end

    test "prints signal to console with correct format", %{signal: signal} do
      output =
        capture_io(fn ->
          assert :ok = ConsoleAdapter.deliver(signal, [])
        end)

      # Verify output contains expected elements
      # Timestamp year
      assert output =~ "[#{DateTime.utc_now().year}"
      assert output =~ "] SIGNAL DISPATCHED"
      assert output =~ "id=#{signal.id}"
      assert output =~ "type=#{signal.type}"
      assert output =~ "source=#{signal.source}"
      assert output =~ "data=%{message: \"test message\", value: 42}"
    end

    test "prints signal with nil data", %{} do
      {:ok, signal} =
        Signal.new(%{
          type: "test.signal",
          source: "/test/source"
          # No data field
        })

      output =
        capture_io(fn ->
          assert :ok = ConsoleAdapter.deliver(signal, [])
        end)

      assert output =~ "id=#{signal.id}"
      assert output =~ "type=#{signal.type}"
      assert output =~ "source=#{signal.source}"
      assert output =~ "data=nil"
    end

    test "prints signal with empty data", %{} do
      {:ok, signal} =
        Signal.new(%{
          type: "test.signal",
          source: "/test/source",
          data: %{}
        })

      output =
        capture_io(fn ->
          assert :ok = ConsoleAdapter.deliver(signal, [])
        end)

      assert output =~ "data=%{}"
    end

    test "prints signal with complex nested data", %{} do
      complex_data = %{
        user: %{
          id: 123,
          profile: %{name: "John Doe", age: 30}
        },
        metadata: %{
          tags: ["important", "urgent"],
          priority: :high
        }
      }

      {:ok, signal} =
        Signal.new(%{
          type: "user.profile.updated",
          source: "/user/service",
          data: complex_data
        })

      output =
        capture_io(fn ->
          assert :ok = ConsoleAdapter.deliver(signal, [])
        end)

      # Check that complex data is pretty-printed
      assert output =~ "user:"
      assert output =~ "profile:"
      assert output =~ "\"John Doe\""
      assert output =~ "tags:"
      assert output =~ "\"important\""
      assert output =~ "priority: :high"
    end

    test "ignores options parameter", %{signal: signal} do
      # Test with various option types
      option_sets = [
        [],
        [timeout: 5000],
        [format: :json, custom: "value"],
        %{map_option: "value"}
      ]

      for opts <- option_sets do
        output =
          capture_io(fn ->
            assert :ok = ConsoleAdapter.deliver(signal, opts)
          end)

        # Output should be same regardless of options
        assert output =~ "SIGNAL DISPATCHED"
        assert output =~ "id=#{signal.id}"
      end
    end

    test "always returns :ok", %{signal: signal} do
      # Test multiple times to ensure consistency
      for _i <- 1..3 do
        capture_io(fn ->
          assert :ok = ConsoleAdapter.deliver(signal, [])
        end)
      end
    end

    test "handles signal with special characters in data", %{} do
      special_data = %{
        unicode: "Hello 世界! 🚀",
        quotes: "String with \"quotes\" and 'apostrophes'",
        symbols: "!@#$%^&*()_+-={}[]|\\:;\"'<>?,./",
        newlines: "Line 1\nLine 2\nLine 3"
      }

      {:ok, signal} =
        Signal.new(%{
          type: "special.characters",
          source: "/test",
          data: special_data
        })

      output =
        capture_io(fn ->
          assert :ok = ConsoleAdapter.deliver(signal, [])
        end)

      # Should handle special characters properly
      assert output =~ "Hello 世界! 🚀"
      assert output =~ "String with \\\"quotes\\\""
      assert output =~ "!@#$%^&*()"
    end

    test "timestamp format is ISO 8601 UTC", %{signal: signal} do
      output =
        capture_io(fn ->
          assert :ok = ConsoleAdapter.deliver(signal, [])
        end)

      # Extract timestamp from output
      [timestamp_line | _] = String.split(output, "\n")
      timestamp_match = Regex.run(~r/\[([^\]]+)\]/, timestamp_line)
      assert timestamp_match, "Could not find timestamp in output: #{timestamp_line}"

      [_, timestamp_str] = timestamp_match

      # Verify it's a valid ISO 8601 timestamp
      assert {:ok, _datetime, 0} = DateTime.from_iso8601(timestamp_str)
    end

    test "multiple signals produce separate outputs", %{} do
      {:ok, signal1} = Signal.new(%{type: "first", source: "/test", data: %{id: 1}})
      {:ok, signal2} = Signal.new(%{type: "second", source: "/test", data: %{id: 2}})

      output =
        capture_io(fn ->
          assert :ok = ConsoleAdapter.deliver(signal1, [])
          assert :ok = ConsoleAdapter.deliver(signal2, [])
        end)

      # Should contain both signals
      assert output =~ "type=first"
      assert output =~ "type=second"
      assert output =~ "id: 1"
      assert output =~ "id: 2"

      # Should contain two "SIGNAL DISPATCHED" headers
      signal_count =
        output
        |> String.split("SIGNAL DISPATCHED")
        |> length()
        # Subtract 1 because split creates empty string before first match
        |> Kernel.-(1)

      assert signal_count == 2
    end
  end

  describe "integration with other components" do
    test "works with Signal.new validation", %{} do
      # Test with minimum required fields
      {:ok, signal} = Signal.new(%{type: "minimal", source: "/test"})

      output =
        capture_io(fn ->
          assert :ok = ConsoleAdapter.deliver(signal, [])
        end)

      assert output =~ "type=minimal"
      assert output =~ "source=/test"
    end

    test "handles all valid signal types", %{} do
      signal_configs = [
        %{type: "simple", source: "/test"},
        %{type: "with.dots", source: "/complex/path"},
        %{type: "user:action", source: "service"},
        %{type: "UPPERCASE", source: "/TEST"},
        %{type: "with_underscores", source: "/test_path"}
      ]

      for config <- signal_configs do
        {:ok, signal} = Signal.new(config)

        output =
          capture_io(fn ->
            assert :ok = ConsoleAdapter.deliver(signal, [])
          end)

        assert output =~ "type=#{config.type}"
        assert output =~ "source=#{config.source}"
      end
    end
  end

  describe "error handling and edge cases" do
    test "handles signal with very long data", %{} do
      long_string = String.duplicate("x", 1000)

      long_data = %{
        long_field: long_string,
        list: Enum.to_list(1..100),
        nested: %{deep: %{very: %{deep: %{data: "here"}}}}
      }

      {:ok, signal} =
        Signal.new(%{
          type: "large.data",
          source: "/test",
          data: long_data
        })

      output =
        capture_io(fn ->
          assert :ok = ConsoleAdapter.deliver(signal, [])
        end)

      # Should handle large data without error
      assert output =~ "type=large.data"
      # Should contain part of the string
      assert output =~ String.slice(long_string, 0, 10)
    end

    test "concurrent deliveries work correctly", %{} do
      {:ok, signal} = Signal.new(%{type: "concurrent", source: "/test", data: %{id: "test"}})

      # Run multiple deliveries concurrently
      tasks =
        for i <- 1..5 do
          Task.async(fn ->
            capture_io(fn ->
              ConsoleAdapter.deliver(signal, task_id: i)
            end)
          end)
        end

      outputs = Task.await_many(tasks)

      # All should complete successfully
      assert length(outputs) == 5

      # All outputs should contain the signal info
      for output <- outputs do
        assert output =~ "type=concurrent"
        assert output =~ "SIGNAL DISPATCHED"
      end
    end
  end
end
