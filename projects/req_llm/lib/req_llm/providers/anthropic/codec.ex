defimpl ReqLLM.Context.Codec, for: ReqLLM.Providers.Anthropic do
  def encode(%ReqLLM.Providers.Anthropic{context: ctx}) do
    {system_prompt, regular_messages} = extract_system_message(ctx)

    %{
      messages: Enum.map(regular_messages, &encode_message/1)
    }
    |> maybe_put_system(system_prompt)
  end

  defp maybe_put_system(map, nil), do: map
  defp maybe_put_system(map, prompt), do: Map.put(map, :system, prompt)

  def decode(%ReqLLM.Providers.Anthropic{context: %{"content" => content}}) do
    content
    |> Enum.map(&decode_content_block/1)
    |> List.flatten()
    |> Enum.reject(&is_nil/1)
  end

  # Private translation helpers
  defp extract_system_message(%ReqLLM.Context{messages: messages}) do
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
         media_type: type
       }) do
    %{
      "type" => "image",
      "source" => %{
        "type" => "base64",
        "media_type" => type,
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

  # Handle image_url type for compatibility
  defp encode_content_part(%ReqLLM.Message.ContentPart{type: :image_url, url: url}) do
    # Note: This is a simplified implementation - real URLs would need processing
    %{
      "type" => "image",
      "source" => %{
        "type" => "base64",
        # Would need proper detection
        "media_type" => "image/jpeg",
        "data" => url |> String.replace(~r/^data:image\/[^;]+;base64,/, "")
      }
    }
  end

  # Decode Anthropic responses back to StreamChunks
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
end
