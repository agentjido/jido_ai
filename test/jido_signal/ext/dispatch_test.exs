defmodule Jido.Signal.Ext.DispatchTest do
  use ExUnit.Case, async: true

  alias __MODULE__.TestDispatchExt, as: DispatchExt
  alias Jido.Signal

  # Define the test dispatch extension inline to avoid compilation issues
  defmodule TestDispatchExt do
    use Jido.Signal.Ext,
      namespace: "dispatch",
      schema: []

    alias Jido.Signal.Dispatch

    # Override the default validation to use dispatch validation
    defoverridable validate_data: 1

    @spec validate_data(term()) :: {:ok, term()} | {:error, String.t()}
    def validate_data(nil), do: {:ok, nil}
    # Delegate to existing dispatch validation logic
    # But handle function clause errors for invalid input types
    def validate_data(data) do
      case Dispatch.validate_opts(data) do
        {:ok, validated_config} -> {:ok, validated_config}
        {:error, reason} -> {:error, "Invalid dispatch configuration: #{inspect(reason)}"}
      end
    rescue
      FunctionClauseError ->
        {:error, "Invalid dispatch configuration: invalid structure"}

      _ ->
        {:error, "Invalid dispatch configuration: validation failed"}
    end

    @impl Jido.Signal.Ext
    def to_attrs(data) do
      # Convert dispatch config to CloudEvents-compliant attribute
      # Use the "dispatch" attribute name for CloudEvents compliance
      %{"dispatch" => serialize_config(data)}
    end

    @impl Jido.Signal.Ext
    def from_attrs(attrs) do
      # Extract dispatch configuration from CloudEvents attributes
      case Map.get(attrs, "dispatch") do
        nil -> nil
        config -> deserialize_config(config)
      end
    end

    # Private helper functions

    defp serialize_config(nil), do: nil

    defp serialize_config({adapter, opts}) when is_atom(adapter) and is_list(opts) do
      # Convert to a map for JSON serialization
      %{
        "adapter" => to_string(adapter),
        "opts" => serialize_opts(opts)
      }
    end

    defp serialize_config(configs) when is_list(configs) do
      Enum.map(configs, &serialize_config/1)
    end

    defp serialize_opts(opts) do
      # Convert keyword list to map with string keys for JSON compatibility
      # Also convert atom values to strings for JSON compatibility
      Map.new(opts, fn {k, v} ->
        {to_string(k), serialize_value(v)}
      end)
    end

    defp serialize_value(v) when is_atom(v) and not is_nil(v) and not is_boolean(v),
      do: to_string(v)

    defp serialize_value(v), do: v

    defp deserialize_config(nil), do: nil

    defp deserialize_config(%{"adapter" => adapter_str, "opts" => opts_map})
         when is_binary(adapter_str) and is_map(opts_map) do
      adapter = String.to_atom(adapter_str)
      opts = deserialize_opts(opts_map)
      {adapter, opts}
    end

    defp deserialize_config(configs) when is_list(configs) do
      Enum.map(configs, &deserialize_config/1)
    end

    defp deserialize_config(config) do
      # For backward compatibility, return as-is if it doesn't match expected format
      config
    end

    defp deserialize_opts(opts_map) when is_map(opts_map) do
      # Convert map with string keys back to keyword list
      # Try to deserialize string values back to atoms for known atom keys
      Enum.map(opts_map, fn {k, v} ->
        key = String.to_atom(k)
        value = deserialize_value(key, v)
        {key, value}
      end)
    end

    # Convert certain string values back to atoms for known keys
    defp deserialize_value(key, value) when key in [:method, :level] and is_binary(value) do
      String.to_atom(value)
    end

    defp deserialize_value(_key, value), do: value
  end

  # Alias for easier reference in tests
  describe "extension registration and basic functionality" do
    test "extension is automatically registered" do
      # Either our test extension or the real extension should be registered
      {:ok, registered_ext} = Jido.Signal.Ext.Registry.get("dispatch")
      assert registered_ext in [DispatchExt, Jido.Signal.Ext.Dispatch]
    end

    test "extension implements required callbacks" do
      assert function_exported?(DispatchExt, :namespace, 0)
      assert function_exported?(DispatchExt, :schema, 0)
      assert function_exported?(DispatchExt, :to_attrs, 1)
      assert function_exported?(DispatchExt, :from_attrs, 1)
      assert function_exported?(DispatchExt, :validate_data, 1)
    end

    test "namespace returns 'dispatch'" do
      assert DispatchExt.namespace() == "dispatch"
    end

    test "schema returns valid structure" do
      schema = DispatchExt.schema()
      assert is_list(schema)
    end
  end

  describe "schema validation for valid dispatch configurations" do
    test "validates single pid dispatch config" do
      config = {:pid, [target: self()]}
      assert {:ok, validated} = DispatchExt.validate_data(config)
      # The dispatch validation may add defaults, so check the essential parts
      {:pid, opts} = validated
      assert opts[:target] == self()
    end

    test "validates single logger dispatch config" do
      config = {:logger, [level: :info]}
      assert {:ok, validated} = DispatchExt.validate_data(config)
      assert validated == config
    end

    test "validates single console dispatch config" do
      config = {:console, []}
      assert {:ok, validated} = DispatchExt.validate_data(config)
      assert validated == config
    end

    test "validates single noop dispatch config" do
      config = {:noop, []}
      assert {:ok, validated} = DispatchExt.validate_data(config)
      assert validated == config
    end

    test "validates single http dispatch config" do
      config = {:http, [url: "https://api.example.com/events", method: :post]}
      assert {:ok, validated} = DispatchExt.validate_data(config)
      # Check the essential parts, as validation may add defaults
      {:http, opts} = validated
      assert opts[:url] == "https://api.example.com/events"
      assert opts[:method] == :post
    end

    test "validates single webhook dispatch config" do
      config = {:webhook, [url: "https://hooks.example.com", secret: "secret123"]}
      assert {:ok, validated} = DispatchExt.validate_data(config)
      # Check the essential parts, as validation may add defaults
      {:webhook, opts} = validated
      assert opts[:url] == "https://hooks.example.com"
      assert opts[:secret] == "secret123"
    end

    test "validates multiple dispatch configs" do
      configs = [
        {:logger, [level: :info]},
        {:console, []},
        {:pid, [target: self()]}
      ]

      assert {:ok, validated} = DispatchExt.validate_data(configs)
      # Check that we got the right number of validated configs
      assert length(validated) == 3
      # Check the essential parts of each config
      [logger_config, console_config, pid_config] = validated
      assert {:logger, logger_opts} = logger_config
      assert logger_opts[:level] == :info
      assert {:console, _} = console_config
      assert {:pid, pid_opts} = pid_config
      assert pid_opts[:target] == self()
    end

    test "validates nil dispatch (no dispatch)" do
      assert {:ok, nil} = DispatchExt.validate_data(nil)
    end

    test "validates empty list dispatch" do
      assert {:ok, []} = DispatchExt.validate_data([])
    end
  end

  describe "schema validation rejects invalid configurations" do
    test "rejects non-atom adapter" do
      config = {"string_adapter", []}
      {:error, error} = DispatchExt.validate_data(config)
      assert error =~ "Invalid dispatch configuration"
    end

    test "rejects non-list opts" do
      config = {:logger, %{level: :info}}
      assert {:error, error} = DispatchExt.validate_data(config)
      assert error =~ "Invalid dispatch configuration"
    end

    test "rejects invalid structure" do
      config = "invalid"
      assert {:error, error} = DispatchExt.validate_data(config)
      assert error =~ "Invalid dispatch configuration"
    end

    test "rejects list with invalid items" do
      configs = [
        {:logger, [level: :info]},
        # Invalid adapter type
        {"invalid", []},
        {:console, []}
      ]

      assert {:error, error} = DispatchExt.validate_data(configs)
      assert error =~ "Invalid dispatch configuration"
    end

    test "rejects map structure" do
      config = %{adapter: :logger, opts: [level: :info]}
      assert {:error, error} = DispatchExt.validate_data(config)
      assert error =~ "Invalid dispatch configuration"
    end
  end

  describe "serialization round-trip" do
    test "serializes and deserializes single dispatch config" do
      original_config = {:pid, [target: self()]}

      # Test serialization
      attrs = DispatchExt.to_attrs(original_config)
      assert is_map(attrs)
      assert Map.has_key?(attrs, "dispatch")

      # Verify CloudEvents compliance - uses string keys
      dispatch_data = attrs["dispatch"]
      assert is_map(dispatch_data)
      assert dispatch_data["adapter"] == "pid"
      assert is_map(dispatch_data["opts"])

      # Test deserialization
      roundtrip_config = DispatchExt.from_attrs(attrs)
      assert roundtrip_config == original_config
    end

    test "serializes and deserializes multiple dispatch configs" do
      original_configs = [
        {:logger, [level: :info]},
        {:console, []},
        {:http, [url: "https://api.example.com", method: :post]}
      ]

      # Test serialization
      attrs = DispatchExt.to_attrs(original_configs)
      assert is_map(attrs)
      assert Map.has_key?(attrs, "dispatch")

      dispatch_data = attrs["dispatch"]
      assert is_list(dispatch_data)
      assert length(dispatch_data) == 3

      # Verify each config is properly serialized
      [logger_config, console_config, http_config] = dispatch_data
      assert logger_config["adapter"] == "logger"
      assert logger_config["opts"]["level"] == "info"
      assert console_config["adapter"] == "console"
      assert http_config["adapter"] == "http"

      # Test deserialization - check components due to ordering
      roundtrip_configs = DispatchExt.from_attrs(attrs)
      assert length(roundtrip_configs) == 3
      [rt_logger, rt_console, rt_http] = roundtrip_configs

      {:logger, rt_logger_opts} = rt_logger
      assert rt_logger_opts[:level] == :info

      assert rt_console == {:console, []}

      {:http, rt_http_opts} = rt_http
      assert rt_http_opts[:url] == "https://api.example.com"
      assert rt_http_opts[:method] == :post
    end

    test "serializes and deserializes nil dispatch" do
      original_config = nil

      attrs = DispatchExt.to_attrs(original_config)
      assert attrs == %{"dispatch" => nil}

      roundtrip_config = DispatchExt.from_attrs(attrs)
      assert roundtrip_config == original_config
    end

    test "serializes complex opts correctly" do
      original_config =
        {:http,
         [
           url: "https://api.example.com/webhook",
           method: :post,
           headers: [{"x-api-key", "secret"}, {"content-type", "application/json"}],
           timeout: 5000
         ]}

      attrs = DispatchExt.to_attrs(original_config)
      dispatch_data = attrs["dispatch"]

      # Verify complex data structures are preserved
      assert dispatch_data["opts"]["url"] == "https://api.example.com/webhook"
      assert dispatch_data["opts"]["method"] == "post"
      assert dispatch_data["opts"]["timeout"] == 5000
      assert is_list(dispatch_data["opts"]["headers"])

      roundtrip_config = DispatchExt.from_attrs(attrs)

      # Compare the components rather than exact equality due to keyword list ordering
      {:http, roundtrip_opts} = roundtrip_config
      {:http, original_opts} = original_config

      assert roundtrip_opts[:url] == original_opts[:url]
      assert roundtrip_opts[:method] == original_opts[:method]
      assert roundtrip_opts[:timeout] == original_opts[:timeout]
      assert roundtrip_opts[:headers] == original_opts[:headers]
    end

    test "handles missing dispatch attribute" do
      attrs = %{"type" => "test.event", "source" => "/test"}
      result = DispatchExt.from_attrs(attrs)
      assert result == nil
    end
  end

  describe "CloudEvents compliance" do
    test "serialized output uses string keys" do
      config = {:logger, [level: :debug, format: :short]}
      attrs = DispatchExt.to_attrs(config)

      # Top level should use string keys
      assert Map.keys(attrs) == ["dispatch"]

      # Nested structure should also use string keys
      dispatch_data = attrs["dispatch"]
      assert is_binary(dispatch_data["adapter"])
      assert is_map(dispatch_data["opts"])

      # Options should be string-keyed
      opts_keys = Map.keys(dispatch_data["opts"])
      assert Enum.all?(opts_keys, &is_binary/1)
    end

    test "attribute name is 'dispatch' for CloudEvents compliance" do
      config = {:console, []}
      attrs = DispatchExt.to_attrs(config)

      # Should use "dispatch" attribute name, not extension namespace
      assert Map.has_key?(attrs, "dispatch")
      refute Map.has_key?(attrs, "jido_dispatch")
    end

    test "serialized format is JSON-compatible" do
      config = {:webhook, [url: "https://example.com", secret: "secret", timeout: 30]}
      attrs = DispatchExt.to_attrs(config)

      # Should be able to encode to JSON and back
      json = Jason.encode!(attrs)
      decoded = Jason.decode!(json)

      roundtrip_config = DispatchExt.from_attrs(decoded)

      # Compare components due to keyword list ordering
      {:webhook, roundtrip_opts} = roundtrip_config
      {:webhook, original_opts} = config

      assert roundtrip_opts[:url] == original_opts[:url]
      assert roundtrip_opts[:secret] == original_opts[:secret]
      assert roundtrip_opts[:timeout] == original_opts[:timeout]
    end
  end

  describe "integration with Signal extension API" do
    setup do
      {:ok, signal} = Signal.new("test.event", %{message: "test"}, source: "/test")
      %{signal: signal}
    end

    test "put_extension with dispatch data", %{signal: signal} do
      dispatch_config = {:logger, [level: :info]}

      {:ok, updated_signal} = Signal.put_extension(signal, "dispatch", dispatch_config)

      assert updated_signal.extensions["dispatch"] == dispatch_config
    end

    test "get_extension retrieves dispatch data", %{signal: signal} do
      dispatch_config = {:console, []}

      {:ok, updated_signal} = Signal.put_extension(signal, "dispatch", dispatch_config)
      retrieved_config = Signal.get_extension(updated_signal, "dispatch")

      assert retrieved_config == dispatch_config
    end

    test "list_extensions includes dispatch", %{signal: signal} do
      {:ok, updated_signal} = Signal.put_extension(signal, "dispatch", {:noop, []})

      extensions = Signal.list_extensions(updated_signal)
      assert "dispatch" in extensions
    end

    test "put_extension validates dispatch config", %{signal: signal} do
      invalid_config = {"invalid", "also_invalid"}

      {:error, error} = Signal.put_extension(signal, "dispatch", invalid_config)
      assert error =~ "Invalid dispatch configuration"
    end

    test "multiple dispatch configs work with extension API", %{signal: signal} do
      dispatch_configs = [
        {:logger, [level: :warning]},
        {:console, []},
        {:noop, []}
      ]

      {:ok, updated_signal} = Signal.put_extension(signal, "dispatch", dispatch_configs)
      retrieved_configs = Signal.get_extension(updated_signal, "dispatch")

      assert retrieved_configs == dispatch_configs
    end

    test "delete_extension removes dispatch data", %{signal: signal} do
      {:ok, updated_signal} = Signal.put_extension(signal, "dispatch", {:logger, []})
      final_signal = Signal.delete_extension(updated_signal, "dispatch")

      assert Signal.get_extension(final_signal, "dispatch") == nil
      refute "dispatch" in Signal.list_extensions(final_signal)
    end
  end

  describe "parallel operation with jido_dispatch field" do
    test "signal can have both jido_dispatch field and dispatch extension" do
      # Create signal with jido_dispatch field
      {:ok, signal} =
        Signal.new("test.event", %{},
          source: "/test",
          jido_dispatch: {:logger, [level: :error]}
        )

      # Add dispatch extension
      {:ok, updated_signal} = Signal.put_extension(signal, "dispatch", {:console, []})

      # Both should coexist
      assert updated_signal.jido_dispatch == {:logger, [level: :error]}
      assert Signal.get_extension(updated_signal, "dispatch") == {:console, []}
    end

    test "extension does not interfere with jido_dispatch functionality" do
      # Create signal with both dispatch mechanisms
      {:ok, signal} =
        Signal.new("test.event", %{},
          source: "/test",
          jido_dispatch: {:noop, []}
        )

      {:ok, signal_with_ext} = Signal.put_extension(signal, "dispatch", {:logger, []})

      # jido_dispatch should be unchanged
      assert signal_with_ext.jido_dispatch == signal.jido_dispatch

      # Extension should work independently
      assert Signal.get_extension(signal_with_ext, "dispatch") == {:logger, []}
    end

    test "different validation results for field vs extension" do
      # Create signal with valid jido_dispatch
      {:ok, signal} =
        Signal.new("test.event", %{},
          source: "/test",
          jido_dispatch: {:console, []}
        )

      # Try to add invalid extension - should fail
      {:error, _} = Signal.put_extension(signal, "dispatch", {"invalid", []})

      # Original jido_dispatch should be unaffected
      assert signal.jido_dispatch == {:console, []}
    end
  end

  describe "edge cases and error handling" do
    test "handles atom keys in serialization" do
      # Even though we expect keyword lists, handle atom keys gracefully
      config = {:test_adapter, [level: :info, timeout: 1000]}

      attrs = DispatchExt.to_attrs(config)
      dispatch_data = attrs["dispatch"]

      # Should convert atom keys to strings
      assert dispatch_data["opts"]["level"] == "info"
      assert dispatch_data["opts"]["timeout"] == 1000
    end

    test "handles empty configs gracefully" do
      empty_configs = []

      attrs = DispatchExt.to_attrs(empty_configs)
      assert attrs["dispatch"] == []

      roundtrip = DispatchExt.from_attrs(attrs)
      assert roundtrip == []
    end

    test "backwards compatible with malformed serialized data" do
      # Test with data that doesn't match expected format
      malformed_attrs = %{"dispatch" => "some_string"}

      result = DispatchExt.from_attrs(malformed_attrs)
      # Should return the data as-is for backward compatibility
      assert result == "some_string"
    end

    test "preserves complex nested structures" do
      complex_config =
        {:custom_adapter,
         [
           nested: %{
             deep: %{value: 42},
             list: [1, 2, 3]
           },
           tuples: [{:a, 1}, {:b, 2}]
         ]}

      attrs = DispatchExt.to_attrs(complex_config)
      roundtrip = DispatchExt.from_attrs(attrs)

      assert roundtrip == complex_config
    end
  end
end
