defmodule JSV.FormatValidator.Default.Optional.IRI do
  @moduledoc false
  @external_resource "priv/grammars/iri.abnf"
  use AbnfParsec,
    abnf_file: "priv/grammars/iri.abnf",
    unbox: [],
    ignore: []

  @doc false
  @spec parse_iri(binary) :: {:ok, URI.t()} | {:error, term}
  def parse_iri(data) do
    case iri(data) do
      {:ok, _, "", _, _, _} -> {:ok, URI.parse(data)}
      _ -> {:error, :invalid_IRI}
    end
  end

  @doc false
  @spec parse_iri_reference(binary) :: {:ok, URI.t()} | {:error, term}
  def parse_iri_reference(data) do
    case iri_reference(data) do
      {:ok, _, "", _, _, _} -> {:ok, URI.parse(data)}
      _ -> {:error, :invalid_IRI_reference}
    end
  end
end
