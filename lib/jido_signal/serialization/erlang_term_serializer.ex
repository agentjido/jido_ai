defmodule Jido.Signal.Serialization.ErlangTermSerializer do
  @moduledoc """
  A serializer that uses Erlang's built-in term format.

  This serializer is particularly useful for Erlang/Elixir clusters where
  data needs to be passed between nodes efficiently. The Erlang term format
  preserves the exact structure and types of Elixir/Erlang data.

  ## Features

  - Preserves exact data types (atoms, tuples, etc.)
  - Efficient for inter-node communication
  - Compact binary representation
  - No intermediate transformations needed

  ## Usage

      # Configure as default serializer
      config :jido, :default_serializer, Jido.Signal.Serialization.ErlangTermSerializer

      # Or use explicitly
      Signal.serialize(signal, serializer: Jido.Signal.Serialization.ErlangTermSerializer)
  """

  @behaviour Jido.Signal.Serialization.Serializer

  alias Jido.Signal.Serialization.TypeProvider

  @doc """
  Serialize given term to Erlang binary format.
  """
  @impl true
  def serialize(term, _opts \\ []) do
    serializable_term = prepare_for_serialization(term)
    {:ok, :erlang.term_to_binary(serializable_term, [:compressed])}
  rescue
    e -> {:error, Exception.message(e)}
  end

  @doc """
  Deserialize given Erlang binary data back to the original term.

  For Erlang terms, type conversion is handled automatically since
  the format preserves the original structure. However, if a specific
  type is requested, we can still convert it.
  """
  @impl true
  def deserialize(binary, config \\ []) do
    result = :erlang.binary_to_term(binary, [:safe])
    result = inflate_extensions_for_deserialization(result)

    # If a specific type is requested, convert to that type
    case Keyword.get(config, :type) do
      nil ->
        {:ok, result}

      type_str ->
        type_provider = Keyword.get(config, :type_provider, TypeProvider)

        converted_result =
          if is_map(result) and not is_struct(result) do
            # Convert map to struct if needed
            target_struct = type_provider.to_struct(type_str)
            struct(target_struct.__struct__, result)
          else
            result
          end

        {:ok, converted_result}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  @doc """
  Checks if the given binary is a valid Erlang term.
  """
  @spec valid_erlang_term?(binary()) :: boolean()
  def valid_erlang_term?(binary) when is_binary(binary) do
    :erlang.binary_to_term(binary, [:safe])
    true
  rescue
    _ -> false
  end

  def valid_erlang_term?(_), do: false

  # Prepare term for serialization by flattening extensions in Signal structs
  defp prepare_for_serialization(%Jido.Signal{} = signal) do
    Jido.Signal.flatten_extensions(signal)
  end

  defp prepare_for_serialization(signals) when is_list(signals) do
    Enum.map(signals, &prepare_for_serialization/1)
  end

  defp prepare_for_serialization(term), do: term

  # Inflate extensions during deserialization for Signal maps
  defp inflate_extensions_for_deserialization(data) when is_list(data) do
    Enum.map(data, &inflate_extensions_for_deserialization/1)
  end

  defp inflate_extensions_for_deserialization(data) when is_map(data) and not is_struct(data) do
    # Check if this looks like a Signal by having required CloudEvents fields
    if is_signal_map?(data) do
      # Convert keys to strings for consistent processing
      string_keyed_data = Map.new(data, fn {k, v} -> {to_string(k), v} end)
      {extensions, remaining_attrs} = Jido.Signal.inflate_extensions(string_keyed_data)

      # Add extensions map to the remaining attributes
      if Enum.empty?(extensions) do
        remaining_attrs
      else
        Map.put(remaining_attrs, "extensions", extensions)
      end
    else
      data
    end
  end

  defp inflate_extensions_for_deserialization(data), do: data

  # Check if a map represents a CloudEvents/Signal structure
  defp is_signal_map?(data) when is_map(data) do
    (Map.has_key?(data, "type") or Map.has_key?(data, :type)) and
      (Map.has_key?(data, "source") or Map.has_key?(data, :source)) and
      (Map.has_key?(data, "specversion") or Map.has_key?(data, :specversion) or
         Map.has_key?(data, "id") or Map.has_key?(data, :id))
  end
end
