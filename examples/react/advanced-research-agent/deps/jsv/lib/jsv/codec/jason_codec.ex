# credo:disable-for-this-file Credo.Check.Readability.Specs

if Code.ensure_loaded?(Jason) do
  defmodule JSV.Codec.JasonCodec do
    alias JSV.Helpers.Traverse

    @moduledoc false

    def supports_formatting? do
      true
    end

    def supports_ordered_formatting? do
      true
    end

    def decode!(json) do
      Jason.decode!(json)
    end

    def decode(json) do
      Jason.decode(json)
    end

    def encode_to_iodata!(data) do
      Jason.encode_to_iodata!(data)
    end

    def format_to_iodata!(data) do
      Jason.encode_to_iodata!(data, pretty: true)
    end

    def to_ordered_data(data, key_sorter) do
      Traverse.postwalk(data, fn
        {:val, map} when is_map(map) ->
          map
          |> Map.to_list()
          |> Enum.sort(fn {ka, _}, {kb, _} -> key_sorter.(ka, kb) end)
          |> Jason.OrderedObject.new()

        {:val, v} ->
          v

        {:key, k} ->
          k

        {:struct, struct, _cont} ->
          # Allow custom structs to be present when ordering data but we cannot
          # enforce the orderding because Jason uses a direct serializer and not
          # a normalizer.
          struct
      end)
    end
  end

  defimpl Jason.Encoder, for: JSV.ValidationError do
    def encode(err, opts) do
      err
      |> JSV.normalize_error()
      |> Jason.Encoder.Map.encode(opts)
    end
  end
end
