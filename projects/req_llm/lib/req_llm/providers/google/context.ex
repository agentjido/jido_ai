defmodule ReqLLM.Providers.Google.Context do
  @moduledoc false
  defstruct [:context]
  @type t :: %__MODULE__{context: ReqLLM.Context.t()}
end

# Protocol implementation for Google-specific context encoding
defimpl ReqLLM.Context.Codec, for: ReqLLM.Providers.Google.Context do
  def encode_request(%{context: %ReqLLM.Context{messages: messages}}) do
    {_system_instruction, regular_messages} = extract_system_message(messages)

    # Google API doesn't support systemInstruction in the main request body
    # System messages are typically converted to user messages or handled differently
    %{contents: Enum.map(regular_messages, &encode_message/1)}
  end

  # Handle wrapper struct with context field containing candidates
  def decode_response(%{context: %{candidates: candidates}}) when is_list(candidates) do
    candidates
    |> Enum.flat_map(&extract_content_from_candidate/1)
    |> List.flatten()
    |> Enum.reject(&is_nil/1)
  end

  def decode_response(%{context: %{"candidates" => candidates}}) when is_list(candidates) do
    candidates
    |> Enum.flat_map(&extract_content_from_candidate/1)
    |> List.flatten()
    |> Enum.reject(&is_nil/1)
  end

  # Handle direct candidates (for backward compatibility)
  def decode_response(%{candidates: candidates}) when is_list(candidates) do
    candidates
    |> Enum.flat_map(&extract_content_from_candidate/1)
    |> List.flatten()
    |> Enum.reject(&is_nil/1)
  end

  # Handle legacy format where candidates might have string keys
  def decode_response(%{"candidates" => candidates}) when is_list(candidates) do
    candidates
    |> Enum.flat_map(&extract_content_from_candidate/1)
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
      role: encode_role(role),
      parts: Enum.map(parts, &encode_content_part/1)
    }
  end

  defp encode_role(:user), do: "user"
  defp encode_role(:assistant), do: "model"
  # System messages are handled separately
  defp encode_role(:system), do: "user"

  defp encode_content_part(%ReqLLM.Message.ContentPart{type: :text, text: text}) do
    %{text: text}
  end

  defp encode_content_part(%ReqLLM.Message.ContentPart{
         type: :image,
         data: data,
         media_type: media_type
       }) do
    %{
      inline_data: %{
        mime_type: media_type,
        data: data
      }
    }
  end

  defp encode_content_part(%ReqLLM.Message.ContentPart{
         type: :tool_call,
         tool_name: name,
         input: input,
         tool_call_id: _id
       }) do
    %{
      function_call: %{
        name: name,
        args: input
      }
    }
  end

  defp encode_content_part(%ReqLLM.Message.ContentPart{
         type: :tool_result,
         output: output,
         tool_call_id: _id
       }) do
    %{
      function_response: %{
        # Google doesn't track function names in responses
        name: "unknown",
        response: output
      }
    }
  end

  # Handle image_url type for compatibility
  defp encode_content_part(%ReqLLM.Message.ContentPart{type: :image_url, url: url}) do
    # Extract base64 data from data URL
    case String.split(url, ",", parts: 2) do
      [header, data] ->
        mime_type =
          case Regex.run(~r/data:([^;]+)/, header) do
            [_, type] -> type
            _ -> "image/jpeg"
          end

        %{
          inline_data: %{
            mime_type: mime_type,
            data: data
          }
        }

      _ ->
        %{text: "[Invalid image URL]"}
    end
  end

  defp extract_content_from_candidate(%{"content" => %{"parts" => parts}}) when is_list(parts) do
    Enum.map(parts, &decode_content_part/1)
  end

  defp extract_content_from_candidate(%{content: %{parts: parts}}) when is_list(parts) do
    Enum.map(parts, &decode_content_part/1)
  end

  defp extract_content_from_candidate(_), do: []

  defp decode_content_part(%{"text" => text}) when is_binary(text) do
    [ReqLLM.StreamChunk.text(text)]
  end

  defp decode_content_part(%{text: text}) when is_binary(text) do
    [ReqLLM.StreamChunk.text(text)]
  end

  defp decode_content_part(%{"function_call" => %{"name" => name, "args" => args}}) do
    [ReqLLM.StreamChunk.tool_call(name, args, %{})]
  end

  defp decode_content_part(%{function_call: %{name: name, args: args}}) do
    [ReqLLM.StreamChunk.tool_call(name, args, %{})]
  end

  defp decode_content_part(_unknown), do: []
end
