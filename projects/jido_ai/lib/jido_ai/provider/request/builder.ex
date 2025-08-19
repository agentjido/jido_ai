defmodule Jido.AI.Provider.Request.Builder do
  @moduledoc """
  Utilities for building API request bodies.
  """

  alias Jido.AI.Provider.Util.Options
  alias Jido.AI.{ContentPart, Message, Model, ObjectSchema}

  @doc """
  Builds OpenAI-style chat completion request body with provider options support.
  """
  @spec build_chat_completion_body(
          module(),
          Model.t(),
          String.t() | [Message.t()],
          String.t() | nil,
          keyword()
        ) :: map()
  def build_chat_completion_body(provider_module, %Model{} = model, prompt, system_prompt, opts) do
    # Convert prompt to messages format
    messages = encode_messages(prompt)

    # Prepend system message if system_prompt is provided
    final_messages =
      if system_prompt do
        [%{role: "system", content: system_prompt} | messages]
      else
        messages
      end

    # Get provider-specific options for this provider
    provider_options = Options.merge_provider_options(model, prompt, opts, %{})
    provider_opts_for_model = Map.get(provider_options, model.provider, %{})

    # Get supported options for this provider
    supported_opts = provider_module.chat_completion_opts()

    base_body =
      opts
      |> Keyword.put(:messages, final_messages)
      |> Keyword.put(:model, model.model)
      |> Keyword.take(supported_opts ++ [:stream])
      |> Map.new()

    # Merge provider-specific options into request body
    Map.merge(base_body, provider_opts_for_model)
  end

  @doc """
  Encodes prompts to OpenAI-style messages format.

  Handles both string prompts (converted to user message) and Message lists
  (converted to OpenAI format).
  """
  @spec encode_messages(String.t() | [Message.t()]) :: [map()]
  def encode_messages(prompt) when is_binary(prompt) do
    [%{role: "user", content: prompt}]
  end

  def encode_messages(messages) when is_list(messages) do
    Enum.map(messages, &encode_message/1)
  end

  @doc """
  Converts a Message struct to OpenAI API format.
  """
  @spec encode_message(Message.t()) :: map()
  def encode_message(%Message{role: role, content: content} = message) do
    base_message = %{
      "role" => Atom.to_string(role),
      "content" => encode_content(content)
    }

    base_message
    |> maybe_put_string("name", message.name)
    |> maybe_put_string("tool_call_id", message.tool_call_id)
    |> maybe_put_list("tool_calls", message.tool_calls)
  end

  @doc """
  Builds a system prompt that includes schema guidance for structured output.
  """
  @spec build_schema_system_prompt(map() | keyword(), String.t() | nil) :: String.t()
  def build_schema_system_prompt(schema, existing_system_prompt) do
    # Convert schema to proper format for JSON encoding
    json_schema =
      case schema do
        schema when is_list(schema) ->
          # Convert keyword list to ObjectSchema format for JSON encoding
          case ObjectSchema.new(properties: schema) do
            {:ok, object_schema} -> object_schema
            {:error, _} -> %{properties: Map.new(schema)}
          end

        schema when is_map(schema) ->
          schema
      end

    schema_prompt = """
    You must respond with valid JSON that conforms to the following JSON schema:

    #{Jason.encode!(json_schema, pretty: true)}

    Ensure your response is valid JSON and matches the schema exactly.
    """

    case existing_system_prompt do
      nil -> schema_prompt
      existing -> existing <> "\n\n" <> schema_prompt
    end
  end

  # Private helpers

  defp encode_content(content) when is_binary(content), do: content

  defp encode_content(content_parts) when is_list(content_parts) do
    # Convert list of ContentPart structs to OpenAI format
    Enum.map(content_parts, &ContentPart.to_map/1)
  end

  defp maybe_put_string(map, _key, nil), do: map
  defp maybe_put_string(map, key, value) when is_binary(value), do: Map.put(map, key, value)

  defp maybe_put_list(map, _key, nil), do: map
  defp maybe_put_list(map, _key, []), do: map
  defp maybe_put_list(map, key, value) when is_list(value), do: Map.put(map, key, value)
end
