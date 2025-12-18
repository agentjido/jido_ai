defmodule JSV.FormatValidator.Default.Optional.URI do
  @moduledoc false
  @external_resource "priv/grammars/uri.abnf"

  use AbnfParsec,
    abnf_file: "priv/grammars/uri.abnf",
    unbox: [],
    ignore: []

  @doc false
  @spec parse_uri(binary) :: {:ok, URI.t()} | {:error, term}
  def parse_uri(data) do
    case uri(data) do
      {:ok, _, "", _, _, _} -> {:ok, URI.parse(data)}
      _ -> {:error, :invalid_URI}
    end
  end

  @doc false
  @spec parse_uri_reference(binary) :: {:ok, URI.t()} | {:error, term}
  def parse_uri_reference(data) do
    case uri_reference(data) do
      {:ok, _, "", _, _, _} -> {:ok, URI.parse(data)}
      _ -> {:error, :invalid_URI_reference}
    end
  end
end
