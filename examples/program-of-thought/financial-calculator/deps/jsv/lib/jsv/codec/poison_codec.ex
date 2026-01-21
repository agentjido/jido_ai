# credo:disable-for-this-file Credo.Check.Readability.Specs

if Code.ensure_loaded?(Poison) do
  defmodule JSV.Codec.PoisonCodec do
    @moduledoc false

    def supports_formatting? do
      true
    end

    def supports_ordered_formatting? do
      false
    end

    def decode!(json) do
      Poison.decode!(json)
    end

    def decode(json) do
      Poison.decode(json)
    end

    def encode_to_iodata!(data) do
      Poison.encode_to_iodata!(data)
    end

    def format_to_iodata!(data) do
      Poison.encode_to_iodata!(data, pretty: true)
    end

    @spec to_ordered_data(term, term) :: no_return()
    def to_ordered_data(_data, _key_sorter) do
      raise "ordered JSON encoding requires Jason"
    end
  end

  defimpl Poison.Encoder, for: JSV.ValidationError do
    def encode(err, opts) do
      err
      |> JSV.normalize_error()
      |> Poison.Encoder.Map.encode(opts)
    end
  end
end
