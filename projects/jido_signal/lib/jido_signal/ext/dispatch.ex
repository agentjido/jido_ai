defmodule Jido.Signal.Ext.Dispatch do
  @moduledoc """
  Dispatch extension for Jido Signals.

  This extension provides the same functionality as the existing `jido_dispatch` field
  through the Signal extension system while maintaining full backward compatibility.
  It allows configuring how signals are routed and delivered to various destinations
  using configurable adapters.

  ## Features

  - Same tuple format as existing `jido_dispatch`: `{adapter, opts}` or list of tuples
  - Reuses existing dispatch validation logic from `Jido.Signal.Dispatch`
  - CloudEvents-compliant serialization with attribute name "dispatch"
  - Full compatibility with all existing dispatch adapters

  ## Supported Adapters

  The extension supports all the same adapters as the existing `jido_dispatch` field:

  * `:pid` - Direct delivery to a specific process
  * `:bus` - Delivery to an event bus (implementation pending)
  * `:named` - Delivery to a named process
  * `:pubsub` - Delivery via PubSub mechanism
  * `:logger` - Log signals using Logger
  * `:console` - Print signals to console
  * `:noop` - No-op adapter for testing/development
  * `:http` - HTTP requests using :httpc
  * `:webhook` - Webhook delivery with signatures

  ## Configuration

  Each dispatch configuration is a tuple of `{adapter_type, options}` where:

  * `adapter_type` - One of the built-in adapter types or a custom module
  * `options` - Keyword list of options specific to the chosen adapter

  Multiple dispatch configurations can be provided as a list to send signals
  to multiple destinations.

  ## Usage

      # Add dispatch extension to a signal
      {:ok, signal} = Jido.Signal.put_extension(signal, "dispatch", 
        {:pid, [target: self()]}
      )

      # Multiple dispatch configs
      {:ok, signal} = Jido.Signal.put_extension(signal, "dispatch", [
        {:logger, [level: :info]},
        {:pubsub, [topic: "events"]}
      ])

      # Retrieve dispatch configuration
      dispatch_config = Jido.Signal.get_extension(signal, "dispatch")

  ## CloudEvents Serialization

  When serialized, the dispatch configuration is converted to a CloudEvents-compliant
  attribute named "dispatch". The serialization preserves the exact tuple structure
  for round-trip compatibility.

  ## Examples

      # Single dispatch configuration
      {:ok, signal} = Jido.Signal.put_extension(signal, "dispatch", 
        {:logger, [level: :debug]}
      )

      # HTTP dispatch with custom headers
      {:ok, signal} = Jido.Signal.put_extension(signal, "dispatch",
        {:http, [
          url: "https://api.example.com/events",
          method: :post,
          headers: [{"x-api-key", "secret"}]
        ]}
      )

      # Webhook dispatch with signature
      {:ok, signal} = Jido.Signal.put_extension(signal, "dispatch",
        {:webhook, [
          url: "https://hooks.example.com/webhook",
          secret: "webhook_secret"
        ]}
      )
  """

  use Jido.Signal.Ext,
    namespace: "dispatch",
    schema: []

  alias Jido.Signal.Dispatch

  # Override the default validation to use dispatch validation
  defoverridable validate_data: 1

  @doc """
  Validates dispatch configuration data using existing dispatch validation logic.

  Delegates to `Jido.Signal.Dispatch.validate_opts/1` to ensure the same validation
  behavior as the existing `jido_dispatch` field.

  ## Parameters
  - `data` - The dispatch configuration to validate

  ## Returns
  `{:ok, validated_data}` if valid, `{:error, reason}` if invalid

  ## Examples

      iex> DispatchExt.validate_data({:logger, [level: :info]})
      {:ok, {:logger, [level: :info]}}

      iex> DispatchExt.validate_data({"invalid", []})
      {:error, "Invalid dispatch configuration: invalid structure"}
  """
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
