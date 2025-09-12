defmodule ReqLLM.Providers.Anthropic.Context do
  @moduledoc false
  defstruct [:context]
  @type t :: %__MODULE__{context: ReqLLM.Context.t()}
end

# Protocol implementation for Anthropic-specific context encoding
defimpl ReqLLM.Context.Codec, for: ReqLLM.Providers.Anthropic.Context do
  def encode(%{context: %ReqLLM.Context{messages: messages}}) do
    {system_prompt, regular_messages} = extract_system_message(messages)

    %{messages: Enum.map(regular_messages, &encode_message/1)}
    |> maybe_put_system(system_prompt)
  end

  # Handle wrapper struct with context field containing content
  def decode(%{context: %{content: content}}) when is_list(content) do
    content
    |> Enum.map(&decode_content_block/1)
    |> List.flatten()
    |> Enum.reject(&is_nil/1)
  end

  def decode(%{context: %{"content" => content}}) when is_list(content) do
    content
    |> Enum.map(&decode_content_block/1)
    |> List.flatten()
    |> Enum.reject(&is_nil/1)
  end

  # Handle direct content (for backward compatibility)
  def decode(%{content: content}) when is_list(content) do
    content
    |> Enum.map(&decode_content_block/1)
    |> List.flatten()
    |> Enum.reject(&is_nil/1)
  end

  # Handle legacy format where content might have string keys
  def decode(%{"content" => content}) when is_list(content) do
    content
    |> Enum.map(&decode_content_block/1)
    |> List.flatten()
    |> Enum.reject(&is_nil/1)
  end

  # Private helpers
  defp extract_system_message(messages) do
    case Enum.split_with(messages, &(&1.role == :system)) do
      {[], regular} -> {nil, regular}
      {[%{content: [%{text: text}]}], regular} -> {text, regular}
      {_multiple, _} -> raise "Multiple system messages not supported"
    end
  end

  defp encode_message(%ReqLLM.Message{role: role, content: parts}) do
    %{
      role: Atom.to_string(role),
      content: Enum.map(parts, &encode_content_part/1)
    }
  end

  defp encode_content_part(%ReqLLM.Message.ContentPart{type: :text, text: text}) do
    %{"type" => "text", "text" => text}
  end

  defp encode_content_part(%ReqLLM.Message.ContentPart{
         type: :image,
         data: data,
         media_type: media_type
       }) do
    %{
      "type" => "image",
      "source" => %{
        "type" => "base64",
        "media_type" => media_type,
        "data" => data
      }
    }
  end

  defp encode_content_part(%ReqLLM.Message.ContentPart{
         type: :tool_call,
         tool_name: name,
         input: input,
         tool_call_id: id
       }) do
    %{
      "type" => "tool_use",
      "id" => id,
      "name" => name,
      "input" => input
    }
  end

  defp encode_content_part(%ReqLLM.Message.ContentPart{
         type: :tool_result,
         output: output,
         tool_call_id: id
       }) do
    %{
      "type" => "tool_result",
      "tool_use_id" => id,
      "content" => output
    }
  end

  # Handle image_url type for compatibility
  defp encode_content_part(%ReqLLM.Message.ContentPart{type: :image_url, url: url}) do
    %{
      "type" => "image",
      "source" => %{
        "type" => "base64",
        "media_type" => "image/jpeg",
        "data" => url |> String.replace(~r/^data:image\/[^;]+;base64,/, "")
      }
    }
  end

  defp decode_content_block(%{"type" => "text", "text" => text}) do
    [ReqLLM.StreamChunk.text(text)]
  end

  defp decode_content_block(%{"type" => "tool_use", "id" => id, "name" => name, "input" => input}) do
    [ReqLLM.StreamChunk.tool_call(name, input, %{id: id})]
  end

  defp decode_content_block(%{"type" => "thinking", "text" => text}) do
    [ReqLLM.StreamChunk.thinking(text)]
  end

  defp decode_content_block(_unknown), do: []

  defp maybe_put_system(map, nil), do: map
  defp maybe_put_system(map, prompt), do: Map.put(map, :system, prompt)
end
