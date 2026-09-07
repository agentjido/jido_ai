defmodule Jido.AI.Turn.Content do
  @moduledoc false
  alias Jido.AI.{Error, Observe}
  alias ReqLLM.Message.ContentPart
  alias ReqLLM.ToolResult

  def format_tool_result_content({:ok, result, _effects}),
    do: format_tool_result_content({:ok, result})

  def format_tool_result_content({:error, error, _effects}),
    do: format_tool_result_content({:error, error})

  def format_tool_result_content({:ok, %ToolResult{} = result}) do
    parts = normalize_content_parts(result.content)

    payload =
      build_tool_result_payload(result.output, json_safe_content_parts(parts), result.metadata)

    encode_tool_result_envelope(%{ok: true, result: payload}, parts)
  end

  def format_tool_result_content({:ok, result}) when is_binary(result),
    do: encode_tool_result_envelope(%{ok: true, result: result})

  def format_tool_result_content({:ok, result}) when is_list(result) do
    if content_parts_list?(result) do
      parts = normalize_content_parts(result)

      payload =
        case json_safe_content_parts(parts) do
          nil -> nil
          safe_parts -> %{content: serialize_content_parts(safe_parts)}
        end

      encode_tool_result_envelope(%{ok: true, result: payload}, parts)
    else
      encode_tool_result_envelope(%{ok: true, result: result})
    end
  end

  def format_tool_result_content({:ok, result}) when is_map(result) do
    case extract_content_parts_result(result) do
      {:ok, output, parts} ->
        # Only include text-safe content parts in the JSON payload.
        # File/binary content parts (e.g., PDFs) cannot be JSON-encoded
        # and are already sent as separate content blocks via `parts`.
        json_payload = build_tool_result_payload(output, json_safe_content_parts(parts))
        encode_tool_result_envelope(%{ok: true, result: json_payload}, parts)

      :error ->
        encode_tool_result_envelope(%{ok: true, result: result})
    end
  end

  def format_tool_result_content({:ok, result}),
    do: encode_tool_result_envelope(%{ok: true, result: result})

  def format_tool_result_content({:error, error}) do
    encode_tool_result_envelope(%{
      ok: false,
      error: Error.normalize(error, :execution_error, "Tool execution failed")
    })
  end

  def format_tool_result_content(other) do
    encode_tool_result_envelope(%{
      ok: false,
      error:
        Error.error_envelope(:invalid_result, "Invalid tool result envelope", %{
          result: inspect(other)
        })
    })
  end

  defp encode_tool_result_envelope(payload, parts \\ [])
       when is_map(payload) and is_list(parts) do
    encoded =
      payload
      |> Observe.sanitize_transport_payload()
      |> Jason.encode!()

    case parts do
      [] -> encoded
      normalized_parts -> [ContentPart.text(encoded) | normalized_parts]
    end
  end

  defp build_tool_result_payload(output, content, metadata \\ %{}) do
    payload =
      %{}
      |> maybe_add(:output, empty_map_to_nil(output))
      |> maybe_add(:content, normalize_tool_result_content_payload(content))
      |> maybe_add(:metadata, empty_map_to_nil(metadata))

    case payload do
      %{output: result} when map_size(payload) == 1 -> result
      %{content: result} when map_size(payload) == 1 -> result
      %{} = map when map_size(map) > 0 -> map
      _ -> nil
    end
  end

  defp extract_content_parts_result(result) do
    case get_field(result, :__content_parts__) do
      parts when is_list(parts) ->
        clean_result =
          result
          |> Map.delete(:__content_parts__)
          |> Map.delete("__content_parts__")

        {:ok, empty_map_to_nil(clean_result), normalize_content_parts(parts)}

      _ ->
        :error
    end
  end

  # File content parts carry raw binary data that can't be JSON-encoded.
  # Only include text-safe parts (text, image_url, video_url, thinking) in the JSON payload.
  defp json_safe_content_parts(parts) when is_list(parts) do
    case Enum.filter(parts, &json_safe_content_part?/1) do
      [] -> nil
      filtered -> filtered
    end
  end

  defp json_safe_content_part?(%ContentPart{type: :file}), do: false

  defp json_safe_content_part?(%ContentPart{type: :image, data: data}) when is_binary(data),
    do: false

  defp json_safe_content_part?(%ContentPart{}), do: true
  defp json_safe_content_part?(_), do: true

  def normalize_content_parts(parts) when is_list(parts) do
    Enum.flat_map(parts, fn
      %ContentPart{} = part ->
        [part]

      text when is_binary(text) ->
        [ContentPart.text(text)]

      %{type: type} = part ->
        case normalize_content_part_map(type, part) do
          nil -> [ContentPart.text(inspect(part))]
          normalized -> [normalized]
        end

      %{"type" => type} = part ->
        case normalize_content_part_map(type, part) do
          nil -> [ContentPart.text(inspect(part))]
          normalized -> [normalized]
        end

      other ->
        [ContentPart.text(inspect(other))]
    end)
  end

  def normalize_content_parts(content) when is_binary(content), do: [ContentPart.text(content)]
  def normalize_content_parts(nil), do: []
  def normalize_content_parts(other), do: [ContentPart.text(inspect(other))]

  defp normalize_content_part_map(type, part) when type in [:text, "text"] do
    text = get_field(part, :text)
    metadata = get_field(part, :metadata, %{})
    if is_binary(text), do: ContentPart.text(text, metadata), else: nil
  end

  defp normalize_content_part_map(type, part) when type in [:thinking, "thinking"] do
    text = get_field(part, :thinking) || get_field(part, :text)
    metadata = get_field(part, :metadata, %{})
    if is_binary(text), do: ContentPart.thinking(text, metadata), else: nil
  end

  defp normalize_content_part_map(type, part) when type in [:image_url, "image_url"] do
    url = get_field(part, :url)
    metadata = get_field(part, :metadata, %{})
    if is_binary(url), do: ContentPart.image_url(url, metadata), else: nil
  end

  defp normalize_content_part_map(type, part) when type in [:image, "image"] do
    data = get_field(part, :data)
    media_type = get_field(part, :media_type, "image/png")
    metadata = get_field(part, :metadata, %{})

    cond do
      is_binary(data) and metadata == %{} -> ContentPart.image(data, media_type)
      is_binary(data) -> ContentPart.image(data, media_type, metadata)
      true -> nil
    end
  end

  defp normalize_content_part_map(type, part)
       when type in [:file, "file", :file_id, "file_id", :document, "document"] do
    file_id = part_binary_field(part, :file_id)
    data = part_field(part, :data)
    filename = part_binary_field(part, :filename)
    media_type = part_binary_field(part, :media_type)

    cond do
      is_binary(file_id) ->
        file_id
        |> ContentPart.file_id(media_type || "application/pdf", part_metadata(part))
        |> maybe_put_filename(filename)

      is_binary(data) and is_binary(filename) ->
        ContentPart.file(data, filename, media_type || "application/octet-stream")

      true ->
        nil
    end
  end

  defp normalize_content_part_map(_, _), do: nil

  defp part_field(part, key) do
    source = part_source(part)
    get_field(part, key) || get_field(source, key)
  end

  defp part_source(part) do
    case get_field(part, :source) do
      %{} = source -> source
      source when is_list(source) -> if(Keyword.keyword?(source), do: Map.new(source), else: %{})
      _source -> %{}
    end
  end

  defp part_binary_field(part, key) do
    case part_field(part, key) do
      value when is_binary(value) ->
        case String.trim(value) do
          "" -> nil
          value -> value
        end

      _value ->
        nil
    end
  end

  defp part_metadata(part) do
    metadata =
      case get_field(part, :metadata) do
        metadata when is_map(metadata) ->
          metadata

        metadata when is_list(metadata) ->
          if(Keyword.keyword?(metadata), do: Map.new(metadata), else: %{})

        _metadata ->
          %{}
      end

    Enum.reduce([:title, :context, :citations], metadata, fn key, acc ->
      case part_field(part, key) do
        nil -> acc
        value -> Map.put_new(acc, key, value)
      end
    end)
  end

  defp maybe_put_filename(part, filename) when is_binary(filename),
    do: %{part | filename: filename}

  defp maybe_put_filename(part, _filename), do: part

  def content_parts_list?(parts) when is_list(parts) and parts != [] do
    Enum.all?(parts, fn
      %ContentPart{} ->
        true

      %{type: type}
      when type in [:text, :thinking, :image_url, :image, :file, :file_id, :document] ->
        true

      %{"type" => type}
      when type in ["text", "thinking", "image_url", "image", "file", "file_id", "document"] ->
        true

      _ ->
        false
    end)
  end

  def content_parts_list?(_), do: false

  defp empty_map_to_nil(%{} = map) when map_size(map) == 0, do: nil
  defp empty_map_to_nil(value), do: value

  defp normalize_tool_result_content_payload(content) when is_list(content) do
    serialize_content_parts(content)
  end

  defp normalize_tool_result_content_payload(nil), do: nil

  defp serialize_content_parts(parts) when is_list(parts) do
    Enum.map(parts, fn
      %ContentPart{} = part ->
        part
        |> Map.from_struct()
        |> Enum.reject(fn
          {:metadata, metadata} -> metadata in [nil, %{}]
          {_key, value} -> is_nil(value)
        end)
        |> Map.new()
    end)
  end

  defp get_field(map, key, default \\ nil),
    do: Map.get(map, key, Map.get(map, Atom.to_string(key), default))

  defp maybe_add(map, _key, nil), do: map
  defp maybe_add(map, key, value), do: Map.put(map, key, value)
end
