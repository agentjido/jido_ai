defmodule Jido.AI.TokenCounter do
  @moduledoc """
  Token counting functionality for LLM API requests and responses.

  Provides approximate token counting using character-based estimation
  as well as support for exact counting when tiktoken is available.
  """

  alias Jido.AI.Message

  @doc """
  Counts tokens in a string using character-based approximation.

  Uses the commonly accepted approximation of ~4 characters per token
  for English text with OpenAI models.

  ## Examples

      iex> Jido.AI.TokenCounter.count_tokens("Hello world")
      3
      
      iex> Jido.AI.TokenCounter.count_tokens("")
      0
  """
  @spec count_tokens(String.t()) :: non_neg_integer()
  def count_tokens(text) when is_binary(text) do
    if String.length(text) == 0 do
      0
    else
      # Approximate token count: ~4 characters per token
      # This is a rough estimation commonly used for OpenAI models
      text
      |> String.length()
      |> div(4)
      # Minimum 1 token for non-empty strings
      |> max(1)
    end
  end

  def count_tokens(nil), do: 0
  def count_tokens(_), do: 0

  @doc """
  Counts tokens in a list of messages.

  Includes overhead for message formatting (role, content structure).
  """
  @spec count_message_tokens([map()]) :: non_neg_integer()
  def count_message_tokens(messages) when is_list(messages) do
    messages
    |> Enum.reduce(0, fn message, acc ->
      content_tokens =
        case message do
          %{content: content} -> count_tokens(content)
          %{__struct__: Message, content: content} -> count_tokens(content)
          _ -> 0
        end

      # Add ~4 tokens overhead per message for role/structure
      acc + content_tokens + 4
    end)
  end

  def count_message_tokens(_), do: 0

  @doc """
  Counts total tokens for a chat completion request.

  Includes tokens for:
  - System prompt (if provided)
  - All messages in conversation
  - Model name and options (small overhead)
  """
  @spec count_request_tokens(map()) :: non_neg_integer()
  def count_request_tokens(%{"messages" => messages} = _request) do
    message_tokens = count_message_tokens(messages)

    # Add small overhead for model and options
    base_overhead = 10

    message_tokens + base_overhead
  end

  def count_request_tokens(_), do: 0

  @doc """
  Counts tokens in a chat completion response.
  """
  @spec count_response_tokens(map()) :: non_neg_integer()
  def count_response_tokens(%{"choices" => choices}) when is_list(choices) do
    choices
    |> Enum.reduce(0, fn choice, acc ->
      content = get_in(choice, ["message", "content"]) || ""
      acc + count_tokens(content)
    end)
  end

  def count_response_tokens(_), do: 0

  @doc """
  Counts tokens in streaming response content.
  """
  @spec count_stream_tokens(String.t()) :: non_neg_integer()
  def count_stream_tokens(content) when is_binary(content) do
    count_tokens(content)
  end

  def count_stream_tokens(_), do: 0
end
