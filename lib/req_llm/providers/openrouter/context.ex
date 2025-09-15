defmodule ReqLLM.Providers.OpenRouter.Context do
  @moduledoc false
  defstruct [:context]
  @type t :: %__MODULE__{context: ReqLLM.Context.t()}
end

# Protocol implementation for OpenRouter-specific context encoding
# OpenRouter uses OpenAI-compatible format
defimpl ReqLLM.Context.Codec, for: ReqLLM.Providers.OpenRouter.Context do
  def encode_request(%{context: %ReqLLM.Context{messages: messages}}) do
    %{messages: Enum.map(messages, &encode_message/1)}
  end

  # Handle OpenRouter response format with "choices" array (OpenAI-compatible)
  def decode_response(%{context: %{"choices" => choices}}) when is_list(choices) do
    choices
    |> Enum.at(0)
    |> case do
      %{"message" => message} -> decode_message(message)
      %{"delta" => delta} -> decode_delta(delta)
      _ -> []
    end
  end

  # Handle direct choice object
  def decode_response(%{context: %{"message" => message}}) do
    decode_message(message)
  end

  def decode_response(%{context: %{"delta" => delta}}) do
    decode_delta(delta)
  end

  # Fallback
  def decode_response(_), do: []

  # Private helpers
  defp encode_message(%ReqLLM.Message{role: role, content: parts}) do
    %{
      "role" => role_to_openrouter_role(role),
      "content" => encode_content_parts(parts)
    }
  end

  defp role_to_openrouter_role(:user), do: "user"
  defp role_to_openrouter_role(:assistant), do: "assistant"
  defp role_to_openrouter_role(:system), do: "system"
  defp role_to_openrouter_role(:tool), do: "tool"
  defp role_to_openrouter_role(role), do: to_string(role)

  defp encode_content_parts([%ReqLLM.Message.ContentPart{type: :text, text: text}]) do
    # Simple case - single text part becomes a string
    text
  end

  defp encode_content_parts(parts) when is_list(parts) do
    # Multiple parts or non-text parts become an array
    Enum.map(parts, &encode_content_part/1)
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
      "type" => "image_url",
      "image_url" => %{
        "url" => "data:#{media_type};base64,#{data}"
      }
    }
  end

  defp encode_content_part(%ReqLLM.Message.ContentPart{type: :image_url, url: url}) do
    %{
      "type" => "image_url",
      "image_url" => %{"url" => url}
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
      "id" => id,
      "function" => %{
        "name" => name,
        "arguments" => Jason.encode!(input)
      }
    }
  end

  defp encode_content_part(%ReqLLM.Message.ContentPart{
         type: :tool_result,
         output: output,
         tool_call_id: id
       }) do
    %{
      "role" => "tool",
      "tool_call_id" => id,
      "content" => output
    }
  end

  defp decode_message(%{"content" => content}) when is_binary(content) and content != "" do
    [ReqLLM.StreamChunk.text(content)]
  end

  defp decode_message(%{"content" => ""}) do
    []
  end

  defp decode_message(%{"content" => content}) when is_list(content) do
    content
    |> Enum.map(&decode_content_part/1)
    |> List.flatten()
    |> Enum.reject(&is_nil/1)
  end

  defp decode_message(%{"tool_calls" => tool_calls}) when is_list(tool_calls) do
    tool_calls
    |> Enum.map(&decode_tool_call/1)
    |> Enum.reject(&is_nil/1)
  end

  defp decode_message(_), do: []

  defp decode_delta(%{"content" => content}) when is_binary(content) do
    [ReqLLM.StreamChunk.text(content)]
  end

  defp decode_delta(%{"tool_calls" => tool_calls}) when is_list(tool_calls) do
    tool_calls
    |> Enum.map(&decode_tool_call/1)
    |> Enum.reject(&is_nil/1)
  end

  defp decode_delta(_), do: []

  defp decode_content_part(%{"type" => "text", "text" => text}) do
    [ReqLLM.StreamChunk.text(text)]
  end

  defp decode_content_part(_), do: []

  defp decode_tool_call(%{
         "id" => id,
         "type" => "function",
         "function" => %{"name" => name, "arguments" => args_json}
       }) do
    case Jason.decode(args_json || "{}") do
      {:ok, args} -> ReqLLM.StreamChunk.tool_call(name, args, %{id: id})
      {:error, _} -> ReqLLM.StreamChunk.tool_call(name, %{}, %{id: id})
    end
  end

  # Handle tool calls without explicit type field (assume function)
  defp decode_tool_call(%{"id" => id, "function" => %{"name" => name, "arguments" => args_json}}) do
    case Jason.decode(args_json || "{}") do
      {:ok, args} -> ReqLLM.StreamChunk.tool_call(name, args, %{id: id})
      {:error, _} -> ReqLLM.StreamChunk.tool_call(name, %{}, %{id: id})
    end
  end

  defp decode_tool_call(_), do: nil
end
