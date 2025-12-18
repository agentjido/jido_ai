defmodule JSV.Codec do
  @moduledoc """
  JSON encoder/decoder based on available implementation.

  First looks for Jason, then Poision, then JSON (available since Elixir 1.18).
  """

  @codec (cond do
            Code.ensure_loaded?(Jason) ->
              JSV.Codec.JasonCodec

            Code.ensure_loaded?(Poison) ->
              JSV.Codec.PoisonCodec

            Code.ensure_loaded?(JSON) ->
              JSV.Codec.NativeCodec

            true ->
              raise "could not define JSON codec for #{inspect(__MODULE__)}\n\n" <>
                      "For Elixir versions lower than 1.18, make sure to declare a JSON parser " <>
                      ~S|dependency such as {:jason, "~> 1.0"}, {:poison, "~> 5.0"} or | <>
                      ~S|{:poison, "~> 6.0"}.|
          end)

  @supports_formatting @codec.supports_formatting?()
  @spec supports_formatting? :: boolean
  def supports_formatting? do
    @supports_formatting
  end

  @supports_ordered_formatting @codec.supports_ordered_formatting?()
  @spec supports_ordered_formatting? :: boolean
  def supports_ordered_formatting? do
    @supports_ordered_formatting
  end

  @type key :: binary | atom
  @type(key_sorter :: (key, key -> boolean), key: binary | atom)

  @doc "Returns the module used for JSON encoding and decoding."
  @spec codec :: module
  def codec do
    @codec
  end

  @doc "Equivalent to `JSON.decode/1`."
  @spec decode(binary) :: {:ok, term} | {:error, term}
  def decode(json) when is_binary(json) do
    @codec.decode(json)
  end

  @doc "Equivalent to `JSON.decode!/1`."
  @spec decode!(binary) :: term
  def decode!(json) when is_binary(json) do
    @codec.decode!(json)
  end

  @doc "Equivalent to `JSON.encode!/1`."
  @spec encode!(term) :: binary
  def encode!(term) do
    IO.iodata_to_binary(@codec.encode_to_iodata!(term))
  end

  @doc "Equivalent to `JSON.encode_to_iodata!/1`."
  @spec encode_to_iodata!(term) :: iodata
  def encode_to_iodata!(term) do
    @codec.encode_to_iodata!(term)
  end

  @doc "Equivalent to `JSON.encode_to_iodata!/1` with human readable indentation."
  @spec format_to_iodata!(term) :: binary
  def format_to_iodata!(term) do
    @codec.format_to_iodata!(term)
  end

  @doc """
  Equivalent to `JSON.encode!/1` with human readable indentation.

  Requires `Jason` or `Poison` for Elixir versions before 1.18 and OTP before
  27.0.
  """
  @spec format!(term) :: binary
  def format!(term) do
    IO.iodata_to_binary(@codec.format_to_iodata!(term))
  end

  @doc """
  Equivalent to `JSON.encode!/1` with map keys ordered according to the sorter
  function.

  The sorter function will be called with two keys from the same map and should
  return `true` if the first argument precedes or is in the same place as the
  second one.

  Requires `Jason` for Elixir versions before 1.18 and OTP before 27.1.

  Data must be normalized before ordered encoding. Passing structs will result
  in an error. Use `JSV.Normalizer.normalize/1` to normalize data in a
  compatible form.
  """
  @spec format_ordered!(term, key_sorter) :: binary
  def format_ordered!(term, key_sorter) do
    IO.iodata_to_binary(format_ordered_to_iodata!(term, key_sorter))
  end

  @doc "Like `format_ordered!/2` but returns iodata instead of strings."
  @spec format_ordered_to_iodata!(term, key_sorter) :: iodata
  def format_ordered_to_iodata!(term, key_sorter) do
    format_ordered_to_iodata!(@codec, term, key_sorter)
  end

  @doc false
  # This is an entrypoint for tests
  @spec format_ordered_to_iodata!(module, term, key_sorter) :: iodata
  def format_ordered_to_iodata!(module, term, key_sorter) do
    term
    |> module.to_ordered_data(key_sorter)
    |> module.format_to_iodata!()
  end
end
