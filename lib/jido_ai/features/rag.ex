defmodule Jido.AI.Features.RAG do
  @moduledoc """
  Retrieval-Augmented Generation (RAG) support for document-enhanced completions.

  Enables models to generate responses augmented with external documents,
  with provider-specific document formatting and citation extraction.

  ## Supported Providers

  - **Cohere**: Native RAG with `documents` parameter (Command-R models)
  - **Google**: Grounding with inline data or Google Search
  - **Anthropic**: Citation support via extended thinking

  ## Document Format

  Documents must be maps with at least a `content` field:

      %{
        content: "Document text...",
        title: "Optional title",
        url: "https://example.com",
        metadata: %{...}
      }

  ## Usage

      # Prepare documents for a provider
      {:ok, formatted} = RAG.prepare_documents(documents, :cohere)

      # Check RAG support
      RAG.supports?(model)

      # Extract citations from response
      {:ok, citations} = RAG.extract_citations(response, :cohere)
  """

  alias Jido.AI.Model

  # Validation limits
  @max_documents 100
  @max_document_size 500_000
  @min_content_length 1

  @type document :: %{
          required(:content) => String.t(),
          optional(:title) => String.t(),
          optional(:url) => String.t(),
          optional(:metadata) => map()
        }

  @type citation :: %{
          text: String.t(),
          document_index: non_neg_integer(),
          start: non_neg_integer(),
          end: non_neg_integer()
        }

  @doc """
  Check if a model supports RAG.

  ## Parameters
    - model: Jido.AI.Model struct

  ## Returns
    Boolean indicating RAG support

  ## Examples

      iex> RAG.supports?(model)
      true
  """
  @spec supports?(Model.t()) :: boolean()
  def supports?(%Model{provider: provider}) do
    provider in [:cohere, :google, :anthropic]
  end

  @doc """
  Prepare documents for a specific provider's RAG format.

  Each provider requires different document formatting:
  - Cohere: List of maps with text/snippet fields
  - Google: Inline data format with content
  - Anthropic: Plain text concatenation with markers

  ## Parameters
    - documents: List of document maps
    - provider: Provider atom

  ## Returns
    - `{:ok, formatted_documents}` on success
    - `{:error, reason}` if provider doesn't support RAG

  ## Examples

      iex> documents = [%{content: "Text", title: "Doc"}]
      iex> RAG.prepare_documents(documents, :cohere)
      {:ok, [%{"text" => "Text", "title" => "Doc"}]}
  """
  @spec prepare_documents([document()], atom()) :: {:ok, list()} | {:error, term()}
  def prepare_documents(documents, provider) when is_list(documents) do
    with :ok <- validate_documents(documents) do
      do_prepare_documents(documents, provider)
    end
  end

  def prepare_documents(_documents, _provider) do
    {:error, "Documents must be a list"}
  end

  defp do_prepare_documents(documents, :cohere) do
    formatted =
      Enum.map(documents, fn doc ->
        case Map.fetch(doc, :content) do
          {:ok, content} ->
            %{
              "text" => content,
              "title" => Map.get(doc, :title, "Document"),
              "id" => Map.get(doc, :id, generate_doc_id())
            }
            |> maybe_add_url(doc)

          :error ->
            throw({:missing_content, "Document missing required :content field"})
        end
      end)

    {:ok, formatted}
  catch
    {:missing_content, reason} -> {:error, reason}
  end

  defp do_prepare_documents(documents, :google) do
    formatted =
      Enum.map(documents, fn doc ->
        case Map.fetch(doc, :content) do
          {:ok, content} ->
            %{
              "inline_data" => %{
                "content" => content,
                "mime_type" => "text/plain"
              }
            }
            |> maybe_add_metadata(doc)

          :error ->
            throw({:missing_content, "Document missing required :content field"})
        end
      end)

    {:ok, formatted}
  catch
    {:missing_content, reason} -> {:error, reason}
  end

  defp do_prepare_documents(documents, :anthropic) do
    # Anthropic doesn't have native RAG, but we can format documents
    # into the system prompt with citation markers
    formatted_text =
      documents
      |> Enum.with_index(1)
      |> Enum.map_join("\n", fn {doc, idx} ->
        case Map.fetch(doc, :content) do
          {:ok, content} ->
            title = Map.get(doc, :title, "Document #{idx}")
            "\n[#{idx}] #{title}\n#{content}\n"

          :error ->
            throw({:missing_content, "Document missing required :content field"})
        end
      end)

    {:ok, formatted_text}
  catch
    {:missing_content, reason} -> {:error, reason}
  end

  defp do_prepare_documents(_documents, provider) do
    {:error, "Provider #{provider} does not support RAG"}
  end

  @doc """
  Extract citations from a RAG-enhanced response.

  Different providers return citations in different formats.
  This function normalizes them to a common structure.

  ## Parameters
    - response: Raw response from provider
    - provider: Provider atom

  ## Returns
    - `{:ok, [citations]}` with normalized citation list
    - `{:ok, []}` if no citations found
    - `{:error, reason}` on failure

  ## Examples

      iex> RAG.extract_citations(response, :cohere)
      {:ok, [%{text: "...", document_index: 0, start: 10, end: 50}]}
  """
  @spec extract_citations(map(), atom()) :: {:ok, [citation()]} | {:error, term()}
  def extract_citations(%{"citations" => citations}, :cohere) when is_list(citations) do
    normalized =
      Enum.map(citations, fn citation ->
        %{
          text: Map.get(citation, "text", ""),
          document_index: Map.get(citation, "document_ids", []) |> List.first() |> parse_int(0),
          start: Map.get(citation, "start", 0),
          end: Map.get(citation, "end", 0)
        }
      end)

    {:ok, normalized}
  end

  def extract_citations(%{"grounding_metadata" => metadata}, :google) do
    # Google returns grounding chunks
    chunks = Map.get(metadata, "grounding_chunks", [])

    citations =
      Enum.map(chunks, fn chunk ->
        %{
          text: Map.get(chunk, "text", ""),
          document_index: 0,
          start: 0,
          end: 0
        }
      end)

    {:ok, citations}
  end

  def extract_citations(_response, :anthropic) do
    # Anthropic doesn't return structured citations
    # Would need to parse [1], [2] style references from text
    {:ok, []}
  end

  def extract_citations(_response, _provider) do
    {:ok, []}
  end

  @doc """
  Build RAG-enhanced options for chat completion.

  Adds provider-specific RAG parameters to the options map.

  ## Parameters
    - documents: List of document maps
    - base_opts: Base options map for chat completion
    - provider: Provider atom

  ## Returns
    - `{:ok, enhanced_opts}` with RAG parameters added
    - `{:error, reason}` if RAG not supported

  ## Examples

      iex> RAG.build_rag_options(documents, %{temperature: 0.7}, :cohere)
      {:ok, %{temperature: 0.7, documents: [...]}}
  """
  @spec build_rag_options([document()], map(), atom()) :: {:ok, map()} | {:error, term()}
  def build_rag_options(documents, base_opts, provider) when is_list(documents) do
    case prepare_documents(documents, provider) do
      {:ok, formatted_docs} ->
        opts =
          case provider do
            :cohere ->
              Map.put(base_opts, :documents, formatted_docs)

            :google ->
              # Google uses grounding in tools parameter
              grounding = %{
                "grounding" => %{
                  "inline_data" => formatted_docs
                }
              }

              Map.put(base_opts, :tools, [grounding])

            :anthropic ->
              # For Anthropic, inject documents into system prompt
              current_system = Map.get(base_opts, :system, "")
              enhanced_system = "#{current_system}\n\nReference Documents:#{formatted_docs}"
              Map.put(base_opts, :system, enhanced_system)
          end

        {:ok, opts}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Private helpers

  # Validation

  defp validate_documents(documents) when is_list(documents) do
    cond do
      documents == [] ->
        {:error, "Documents list cannot be empty"}

      length(documents) > @max_documents ->
        {:error, "Too many documents: maximum is #{@max_documents}, got #{length(documents)}"}

      true ->
        validate_document_contents(documents)
    end
  end

  defp validate_documents(_), do: {:error, "Documents must be a list"}

  defp validate_document_contents(documents) do
    Enum.reduce_while(documents, :ok, fn doc, _acc ->
      case validate_single_document(doc) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp validate_single_document(doc) when is_map(doc) do
    cond do
      not Map.has_key?(doc, :content) ->
        {:error, "Document missing required :content field"}

      not is_binary(doc.content) ->
        {:error, "Document :content must be a string"}

      String.length(doc.content) < @min_content_length ->
        {:error, "Document content cannot be empty"}

      String.length(doc.content) > @max_document_size ->
        {:error,
         "Document content too large: maximum is #{@max_document_size} characters, got #{String.length(doc.content)}"}

      true ->
        :ok
    end
  end

  defp validate_single_document(_), do: {:error, "Document must be a map"}

  # Document formatting helpers

  defp maybe_add_url(doc_map, %{url: url}) when is_binary(url) do
    Map.put(doc_map, "url", url)
  end

  defp maybe_add_url(doc_map, _), do: doc_map

  defp maybe_add_metadata(doc_map, %{metadata: metadata}) when is_map(metadata) do
    Map.put(doc_map, "metadata", metadata)
  end

  defp maybe_add_metadata(doc_map, _), do: doc_map

  defp generate_doc_id do
    "doc_#{System.unique_integer([:positive, :monotonic])}"
  end

  defp parse_int(value, _default) when is_integer(value), do: value

  defp parse_int(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} -> int
      :error -> default
    end
  end

  defp parse_int(_, default), do: default
end
