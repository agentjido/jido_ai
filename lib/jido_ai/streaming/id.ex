defmodule Jido.AI.Streaming.ID do
  @moduledoc """
  Stream identifier generation and validation helpers.
  """

  alias Bitwise, as: BW

  require Bitwise

  @doc """
  Generates a UUID v4 stream identifier.
  """
  @spec generate_stream_id() :: String.t()
  def generate_stream_id do
    <<a::32, b::16, c::16, d::16, e::48>> = :crypto.strong_rand_bytes(16)

    c = BW.band(c, 0x0FFF) |> BW.bor(0x4000)
    d = BW.band(d, 0x3FFF) |> BW.bor(0x8000)

    [
      to_hex(<<a::32>>, 8),
      "-",
      to_hex(<<b::16>>, 4),
      "-",
      to_hex(<<c::16>>, 4),
      "-",
      to_hex(<<d::16>>, 4),
      "-",
      to_hex(<<e::48>>, 12)
    ]
    |> IO.iodata_to_binary()
  end

  @doc """
  Validates that a stream identifier matches UUID v4 format.
  """
  @spec validate_stream_id(String.t()) :: {:ok, String.t()} | {:error, atom()}
  def validate_stream_id(stream_id) when is_binary(stream_id) do
    uuid_pattern = ~r/^
      [0-9a-f]{8}-
      [0-9a-f]{4}-
      4[0-9a-f]{3}-
      [89ab][0-9a-f]{3}-
      [0-9a-f]{12}
    $/x

    if Regex.match?(uuid_pattern, stream_id) do
      {:ok, stream_id}
    else
      {:error, :invalid_stream_id_format}
    end
  end

  def validate_stream_id(_), do: {:error, :invalid_stream_id_type}

  defp to_hex(data, chars) do
    encoded = Base.encode16(data, case: :lower)
    binary_part(encoded, 0, chars)
  end
end
