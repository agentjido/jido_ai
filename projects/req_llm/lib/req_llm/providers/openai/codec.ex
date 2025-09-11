defimpl ReqLLM.Context.Codec, for: ReqLLM.Providers.OpenAI do
  def encode(%ReqLLM.Providers.OpenAI{context: ctx}) do
    %{
      messages: encode_messages(ctx)
    }
  end

  def decode(%ReqLLM.Providers.OpenAI{context: %{"choices" => choices}}) do
    choices
    |> Enum.flat_map(&decode_choice/1)
    |> Enum.reject(&is_nil/1)
  end

  # Private translation helpers

  defp encode_messages(%ReqLLM.Context{messages: messages}) do
    Enum.map(messages, &encode_message/1)
  end

  defp encode_message(%ReqLLM.Message{role: role, content: parts}) do
    %{
      "role" => map_role(role),
      "content" => encode_content(parts)
    }
  end

  defp map_role(:system), do: "system"
  defp map_role(:user), do: "user"
  defp map_role(:assistant), do: "assistant"
  defp map_role(role), do: Atom.to_string(role)

  defp encode_content([%ReqLLM.Message.ContentPart{type: :text, text: text}]) do
    text
  end

  defp encode_content(parts) when is_list(parts) do
    Enum.map(parts, &encode_content_part/1)
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
      "type" => "image_url",
      "image_url" => %{
        "url" => "data:#{type};base64,#{data}"
      }
    }
  end

  defp encode_content_part(%ReqLLM.Message.ContentPart{type: :image_url, url: url}) do
    %{
      "type" => "image_url",
      "image_url" => %{
        "url" => url
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
      "type" => "function",
      "function" => %{
        "name" => name,
        "arguments" => Jason.encode!(input)
      },
      "id" => id
    }
  end

  # Decode OpenAI responses back to StreamChunks
  defp decode_choice(%{"message" => message}) do
    decode_message(message)
  end

  defp decode_choice(_), do: []

  defp decode_message(%{"content" => content}) when is_binary(content) and content != "" do
    [ReqLLM.StreamChunk.text(content)]
  end

  defp decode_message(%{"tool_calls" => tool_calls}) when is_list(tool_calls) do
    Enum.map(tool_calls, &decode_tool_call/1)
  end

  defp decode_message(_), do: []

  defp decode_tool_call(%{
         "id" => id,
         "function" => %{"name" => name, "arguments" => arguments}
       }) do
    input =
      case Jason.decode(arguments) do
        {:ok, parsed} -> parsed
        {:error, _} -> %{}
      end

    ReqLLM.StreamChunk.tool_call(name, input, %{id: id})
  end

  defp decode_tool_call(_), do: nil
end