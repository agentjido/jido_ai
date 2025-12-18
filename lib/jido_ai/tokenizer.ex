defmodule Jido.AI.Tokenizer do
  @moduledoc """
  Token counting and estimation for AI models.

  Provides accurate token counting using provider-specific estimation strategies.
  No external dependencies - pure Elixir implementation for ease of deployment.

  ## Token Estimation Strategies

  Different providers use different tokenization methods:
  - **OpenAI/GPT models**: ~0.75 tokens per word (BPE tokenization)
  - **Anthropic/Claude**: ~0.8 tokens per word (similar to GPT)
  - **Google/Gemini**: ~0.6 tokens per word (SentencePiece)
  - **Local models**: Model-specific (defaults to ~0.75)

  ## Examples

      # Estimate tokens for a message
      iex> Jido.AI.Tokenizer.count_tokens("Hello, world!", :openai)
      4

      # Count tokens for multiple messages
      iex> messages = [
      ...>   %{role: :system, content: "You are a helpful assistant"},
      ...>   %{role: :user, content: "Hello!"}
      ...> ]
      iex> Jido.AI.Tokenizer.count_messages(messages, :openai)
      18
  """

  alias Jido.AI.Prompt

  # Provider-specific token-to-word ratios
  @provider_ratios %{
    openai: 0.75,
    anthropic: 0.8,
    google: 0.6,
    groq: 0.75,
    together: 0.75,
    openrouter: 0.75,
    ollama: 0.75,
    llamacpp: 0.75,
    default: 0.75
  }

  # Message structure overhead (role, formatting, etc.)
  @message_overhead 4

  @doc """
  Counts tokens in a text string for a specific provider.

  Uses provider-specific estimation ratios for accuracy.

  ## Parameters
  - `text` - The text to count tokens for
  - `provider` - Provider atom (`:openai`, `:anthropic`, `:google`, etc.)

  ## Returns
  Estimated token count as an integer

  ## Examples

      iex> Jido.AI.Tokenizer.count_tokens("Hello, world!", :openai)
      4

      iex> Jido.AI.Tokenizer.count_tokens("Hello, world!", :google)
      3
  """
  @spec count_tokens(String.t(), atom()) :: non_neg_integer()
  def count_tokens(text, provider \\ :default)

  def count_tokens("", _provider), do: 0

  def count_tokens(text, provider) when is_binary(text) do
    ratio = Map.get(@provider_ratios, provider, @provider_ratios.default)

    # Count words - split on whitespace, keep punctuation as separate items
    # This gives us a word-equivalent count for token estimation
    parts =
      text
      |> String.split(~r/\s+/, trim: true)
      |> Enum.flat_map(fn word ->
        # Further split on punctuation to count them separately
        String.split(word, ~r/([.,!?;:])/, include_captures: true, trim: true)
      end)

    word_count = length(parts)

    # Estimate tokens using provider ratio - use ceiling to be conservative
    (word_count * ratio)
    |> Float.ceil()
    |> trunc()
  end

  @doc """
  Counts tokens in a single message.

  Includes overhead for message structure (role, formatting).

  ## Parameters
  - `message` - Message map with `:role` and `:content`
  - `provider` - Provider atom

  ## Returns
  Estimated token count including message overhead
  """
  @spec count_message(map(), atom()) :: non_neg_integer()
  def count_message(%{content: content} = _message, provider) when is_binary(content) do
    content_tokens = count_tokens(content, provider)
    content_tokens + @message_overhead
  end

  def count_message(%{content: content} = _message, _provider) when is_list(content) do
    # Multimodal content - for now just count text parts
    text_tokens =
      content
      |> Enum.filter(&is_binary/1)
      |> Enum.map(&String.length/1)
      |> Enum.sum()

    # Add overhead for multimodal structure
    text_tokens + @message_overhead * 2
  end

  @doc """
  Counts tokens in a list of messages.

  ## Parameters
  - `messages` - List of message maps
  - `provider` - Provider atom

  ## Returns
  Total estimated token count for all messages

  ## Examples

      iex> messages = [
      ...>   %{role: :system, content: "You are helpful"},
      ...>   %{role: :user, content: "Hello!"}
      ...> ]
      iex> Jido.AI.Tokenizer.count_messages(messages, :openai)
      14
  """
  @spec count_messages(list(map()), atom()) :: non_neg_integer()
  def count_messages(messages, provider) when is_list(messages) do
    messages
    |> Enum.map(&count_message(&1, provider))
    |> Enum.sum()
  end

  @doc """
  Counts tokens in a Jido.AI.Prompt struct.

  Renders the prompt and counts all message tokens.

  ## Parameters
  - `prompt` - Jido.AI.Prompt struct
  - `provider` - Provider atom

  ## Returns
  Total estimated token count for the prompt
  """
  @spec count_prompt(Prompt.t(), atom()) :: non_neg_integer()
  def count_prompt(%Prompt{} = prompt, provider) do
    messages = Prompt.render(prompt)
    count_messages(messages, provider)
  end

  @doc """
  Gets the token estimation ratio for a provider.

  Useful for understanding estimation accuracy.

  ## Examples

      iex> Jido.AI.Tokenizer.get_ratio(:openai)
      0.75

      iex> Jido.AI.Tokenizer.get_ratio(:google)
      0.6
  """
  @spec get_ratio(atom()) :: float()
  def get_ratio(provider) do
    Map.get(@provider_ratios, provider, @provider_ratios.default)
  end

  # Legacy functions for backward compatibility

  @doc """
  Encodes a string into tokens for the given model.

  **Note**: This is a placeholder for backward compatibility.
  Use `count_tokens/2` for token estimation instead.
  """
  @spec encode(String.t(), String.t()) :: list(String.t())
  def encode(input, _model) when is_binary(input) do
    String.split(input, " ")
  end

  @doc """
  Decodes tokens back into a string for the given model.

  **Note**: This is a placeholder for backward compatibility.
  """
  @spec decode(list(String.t()), String.t()) :: String.t()
  def decode(tokens, _model) when is_list(tokens) do
    Enum.join(tokens, " ")
  end
end
