defmodule Jido.AI.Query do
  @moduledoc "Shared schema and helpers for text or multimodal user queries."

  alias ReqLLM.Message.ContentPart

  @type t :: String.t() | [ContentPart.t() | map()]
  @typedoc "Uploaded file reference accepted by generated request helpers."
  @type file_reference :: String.t() | keyword() | map()
  @content_part_types [:text, :image, :image_url, :video_url, :file, :file_id, :document, :thinking]
  @content_part_type_strings Enum.map(@content_part_types, &Atom.to_string/1)
  @content_part_type_values @content_part_types ++ @content_part_type_strings
  @file_part_types [:file, :file_id, :document]
  @file_part_type_strings Enum.map(@file_part_types, &Atom.to_string/1)
  @file_part_type_values @file_part_types ++ @file_part_type_strings
  @file_metadata_keys [:title, :context, :citations]

  @doc "Returns a Zoi schema that accepts text or a non-empty list of ReqLLM content parts."
  @spec schema(keyword()) :: Zoi.schema()
  def schema(opts \\ []) do
    description = Keyword.get(opts, :description, "User query or multimodal content parts")

    Zoi.union(
      [
        Zoi.string(description: description),
        Zoi.list(Zoi.any(), description: description)
        |> Zoi.refine({__MODULE__, :validate_content_parts, []})
      ],
      opts
    )
  end

  @doc "Validates that a parsed multimodal query is a non-empty list of content parts."
  @spec validate_content_parts(term(), keyword()) :: :ok | {:error, String.t()}
  def validate_content_parts([_ | _] = parts, _opts) do
    if Enum.all?(parts, &content_part?/1) do
      :ok
    else
      {:error, "query content must be a non-empty list of ReqLLM content parts"}
    end
  end

  def validate_content_parts(_parts, _opts),
    do: {:error, "query content must be a non-empty list of ReqLLM content parts"}

  @doc "Returns true when a term is a ReqLLM content part or compatible content-part map."
  @spec content_part?(term()) :: boolean()
  def content_part?(%ContentPart{}), do: true

  def content_part?(%{type: type}) when type in @content_part_type_values, do: true

  def content_part?(%{"type" => type}) when type in @content_part_type_strings, do: true

  def content_part?(_part), do: false

  @doc """
  Appends uploaded file references from request options to a text or content-part query.

  Supports `:file_id`, `:file_ids`, `:file_reference`, and `:file_references`.
  File references can be strings, keyword lists, or maps with `:file_id`/`"file_id"`
  plus optional `:media_type`, `:filename`, `:metadata`, `:title`, `:context`, or
  `:citations`.

  Returns an explicit unsupported error when the active ReqLLM version does not
  expose `ReqLLM.Message.ContentPart.file_id/3`.
  """
  @spec attach_file_references(t(), keyword()) :: {:ok, t()} | {:error, term()}
  def attach_file_references(query, opts) when is_list(opts) do
    case file_references_from_opts(opts) do
      [] ->
        {:ok, query}

      references ->
        with {:ok, references} <- normalize_file_references(references),
             :ok <- ensure_file_reference_support() do
          file_parts = build_file_reference_parts(references)
          {:ok, query_to_parts(query) ++ file_parts}
        end
    end
  end

  @doc "Builds a text summary for event metadata without discarding the original query."
  @spec summarize(t()) :: String.t()
  def summarize(query) when is_binary(query), do: query

  def summarize(parts) when is_list(parts) do
    Enum.map_join(parts, "\n", fn
      %ContentPart{type: :text, text: text} when is_binary(text) ->
        text

      %ContentPart{type: type} when type in [:image, :image_url] ->
        "[Image]"

      %ContentPart{type: :file, filename: filename} when is_binary(filename) ->
        "[File: #{filename}]"

      %ContentPart{type: :file} ->
        "[File]"

      %{type: type, text: text} when type in [:text, "text"] and is_binary(text) ->
        text

      %{type: type} when type in [:image, :image_url, "image", "image_url"] ->
        "[Image]"

      %{type: type, filename: filename} when type in @file_part_type_values and is_binary(filename) ->
        "[File: #{filename}]"

      %{type: type} when type in @file_part_type_values ->
        "[File]"

      %{"type" => type, "text" => text} when type == "text" and is_binary(text) ->
        text

      %{"type" => type} when type in ["image", "image_url"] ->
        "[Image]"

      %{"type" => type, "filename" => filename} when type in @file_part_type_strings and is_binary(filename) ->
        "[File: #{filename}]"

      %{"type" => type} when type in @file_part_type_strings ->
        "[File]"

      part ->
        inspect(part)
    end)
  end

  defp file_references_from_opts(opts) do
    []
    |> maybe_add_reference(Keyword.get(opts, :file_id))
    |> maybe_add_references(Keyword.get(opts, :file_ids))
    |> maybe_add_reference(Keyword.get(opts, :file_reference))
    |> maybe_add_references(Keyword.get(opts, :file_references))
  end

  defp maybe_add_reference(acc, nil), do: acc
  defp maybe_add_reference(acc, ""), do: acc
  defp maybe_add_reference(acc, reference), do: acc ++ [reference]

  defp maybe_add_references(acc, nil), do: acc
  defp maybe_add_references(acc, []), do: acc

  defp maybe_add_references(acc, references) when is_list(references) do
    if keyword_reference?(references) do
      acc ++ [references]
    else
      acc ++ references
    end
  end

  defp maybe_add_references(acc, reference), do: maybe_add_reference(acc, reference)

  defp keyword_reference?(value) when is_list(value) do
    Keyword.keyword?(value) and
      Enum.any?(
        [:file_id, :source, :media_type, :metadata, :filename, :title, :context, :citations],
        &Keyword.has_key?(value, &1)
      )
  end

  defp keyword_reference?(_value), do: false

  defp ensure_file_reference_support do
    if function_exported?(ContentPart, :file_id, 3) do
      :ok
    else
      {:error, {:unsupported_content_part_file_id, "ReqLLM.Message.ContentPart.file_id/3 is required"}}
    end
  end

  defp build_file_reference_parts(references) do
    Enum.map(references, &build_file_reference_part/1)
  end

  defp build_file_reference_part(attrs) do
    file_id = attrs.file_id
    media_type = attrs.media_type || "application/pdf"
    metadata = attrs.metadata || %{}

    part = apply(ContentPart, :file_id, [file_id, media_type, metadata])

    maybe_put_filename(part, attrs.filename)
  end

  defp normalize_file_references(references) do
    references
    |> Enum.reduce_while({:ok, []}, fn reference, {:ok, acc} ->
      case normalize_file_reference(reference) do
        {:ok, reference} -> {:cont, {:ok, [reference | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, references} -> {:ok, Enum.reverse(references)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp normalize_file_reference(file_id) when is_binary(file_id) do
    case String.trim(file_id) do
      "" -> {:error, {:invalid_file_reference, :missing_file_id}}
      file_id -> {:ok, %{file_id: file_id, media_type: nil, metadata: %{}, filename: nil}}
    end
  end

  defp normalize_file_reference(reference) when is_list(reference) do
    if Keyword.keyword?(reference) do
      reference
      |> Map.new()
      |> normalize_file_reference()
    else
      {:error, {:invalid_file_reference, :missing_file_id}}
    end
  end

  defp normalize_file_reference(%{} = reference) do
    file_id = Map.get(reference, :file_id) || Map.get(reference, "file_id")
    source = Map.get(reference, :source) || Map.get(reference, "source")

    file_id =
      file_id ||
        if(is_map(source), do: Map.get(source, :file_id) || Map.get(source, "file_id"))

    with {:ok, file_id} <- normalize_file_id(file_id) do
      {:ok,
       %{
         file_id: file_id,
         media_type: normalize_optional_binary(reference_value(reference, source, :media_type)),
         metadata: reference_metadata(reference),
         filename: normalize_optional_binary(reference_value(reference, source, :filename))
       }}
    end
  end

  defp normalize_file_reference(_reference), do: {:error, {:invalid_file_reference, :missing_file_id}}

  defp normalize_file_id(file_id) when is_binary(file_id) do
    case String.trim(file_id) do
      "" -> {:error, {:invalid_file_reference, :missing_file_id}}
      file_id -> {:ok, file_id}
    end
  end

  defp normalize_file_id(_file_id), do: {:error, {:invalid_file_reference, :missing_file_id}}

  defp reference_value(reference, source, key) do
    Map.get(reference, key) ||
      Map.get(reference, Atom.to_string(key)) ||
      if(is_map(source), do: Map.get(source, key) || Map.get(source, Atom.to_string(key)))
  end

  defp reference_metadata(reference) do
    metadata =
      case Map.get(reference, :metadata) || Map.get(reference, "metadata") do
        metadata when is_map(metadata) -> metadata
        metadata when is_list(metadata) -> if(Keyword.keyword?(metadata), do: Map.new(metadata), else: %{})
        _metadata -> %{}
      end

    Enum.reduce(@file_metadata_keys, metadata, fn key, acc ->
      value = Map.get(reference, key) || Map.get(reference, Atom.to_string(key))

      if is_nil(value) do
        acc
      else
        Map.put_new(acc, key, value)
      end
    end)
  end

  defp normalize_optional_binary(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      value -> value
    end
  end

  defp normalize_optional_binary(_value), do: nil

  defp query_to_parts(query) when is_binary(query), do: [ContentPart.text(query)]
  defp query_to_parts(query) when is_list(query), do: query

  defp maybe_put_filename(part, filename) when is_binary(filename) and filename != "" do
    %{part | filename: filename}
  end

  defp maybe_put_filename(part, _filename), do: part
end
