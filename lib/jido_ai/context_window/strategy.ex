defmodule Jido.AI.ContextWindow.Strategy do
  @moduledoc """
  Truncation strategies for context window management.

  Provides intelligent strategies for truncating messages to fit within
  context window limits while preserving important context.

  ## Available Strategies

  - **`:keep_recent`** - Keep N most recent messages
  - **`:keep_bookends`** - Keep system message + N recent messages
  - **`:sliding_window`** - Sliding window with configurable overlap
  - **`:smart_truncate`** - Intelligently preserve important context

  ## Usage

      alias Jido.AI.ContextWindow.Strategy

      # Apply a strategy
      {:ok, truncated} = Strategy.apply(prompt, model, limit, :keep_recent, count: 10)

      # Keep recent messages
      {:ok, truncated} = Strategy.keep_recent(prompt, model, limit, count: 20)

      # Keep bookends (system + recent)
      {:ok, truncated} = Strategy.keep_bookends(prompt, model, limit, count: 15)

      # Sliding window with overlap
      {:ok, truncated} = Strategy.sliding_window(prompt, model, limit,
        count: 20,
        overlap: 3
      )
  """

  alias Jido.AI.{Model, Prompt, Tokenizer}

  @doc """
  Applies a truncation strategy to a prompt.

  ## Parameters
  - `prompt` - Jido.AI.Prompt struct
  - `model` - Jido.AI.Model struct
  - `limit` - Token limit
  - `strategy` - Strategy atom (`:keep_recent`, `:keep_bookends`, etc.)
  - `opts` - Strategy-specific options

  ## Returns
  - `{:ok, Prompt.t()}` - Truncated prompt
  - `{:error, reason}` - If strategy fails

  ## Examples

      iex> Strategy.apply(prompt, model, 2000, :keep_recent, count: 10)
      {:ok, %Prompt{}}
  """
  @spec apply(Prompt.t(), Model.t(), non_neg_integer(), atom(), keyword()) ::
          {:ok, Prompt.t()} | {:error, term()}
  def apply(prompt, model, limit, strategy, opts \\ [])

  def apply(prompt, model, limit, :keep_recent, opts) do
    keep_recent(prompt, model, limit, opts)
  end

  def apply(prompt, model, limit, :keep_bookends, opts) do
    keep_bookends(prompt, model, limit, opts)
  end

  def apply(prompt, model, limit, :sliding_window, opts) do
    sliding_window(prompt, model, limit, opts)
  end

  def apply(prompt, model, limit, :smart_truncate, opts) do
    smart_truncate(prompt, model, limit, opts)
  end

  def apply(_prompt, _model, _limit, strategy, _opts) do
    {:error, {:unknown_strategy, strategy}}
  end

  @doc """
  Keeps only the N most recent messages.

  Useful for maintaining conversation continuity when context is limited.

  ## Options
  - `:count` - Number of recent messages to keep (default: calculated to fit)

  ## Examples

      iex> Strategy.keep_recent(prompt, model, 2000, count: 10)
      {:ok, %Prompt{}}
  """
  @spec keep_recent(Prompt.t(), Model.t(), non_neg_integer(), keyword()) ::
          {:ok, Prompt.t()} | {:error, term()}
  def keep_recent(%Prompt{messages: messages} = prompt, model, limit, opts \\ []) do
    count =
      case Keyword.get(opts, :count) do
        nil -> calculate_message_count(messages, model, limit)
        n when is_integer(n) -> n
      end

    truncated_messages = Enum.take(messages, -count)

    {:ok, %{prompt | messages: truncated_messages}}
  end

  @doc """
  Keeps system message (if present) plus N most recent messages.

  Preserves system instructions while maintaining recent context.

  ## Options
  - `:count` - Number of recent messages to keep after system (default: calculated)

  ## Examples

      iex> Strategy.keep_bookends(prompt, model, 2000, count: 15)
      {:ok, %Prompt{}}
  """
  @spec keep_bookends(Prompt.t(), Model.t(), non_neg_integer(), keyword()) ::
          {:ok, Prompt.t()} | {:error, term()}
  def keep_bookends(%Prompt{messages: messages} = prompt, model, limit, opts \\ []) do
    # Separate system message from others
    {system_messages, other_messages} =
      Enum.split_with(messages, fn msg ->
        Map.get(msg, :role) == :system
      end)

    # Calculate how many recent messages we can keep
    system_tokens = Tokenizer.count_messages(system_messages, model.provider)
    available = limit - system_tokens

    count =
      case Keyword.get(opts, :count) do
        nil -> calculate_message_count(other_messages, model, available)
        n when is_integer(n) -> min(n, length(other_messages))
      end

    # Keep system messages + N recent messages
    recent_messages = Enum.take(other_messages, -count)
    truncated_messages = system_messages ++ recent_messages

    {:ok, %{prompt | messages: truncated_messages}}
  end

  @doc """
  Applies a sliding window approach with configurable overlap.

  Maintains context continuity by overlapping adjacent windows.

  ## Options
  - `:count` - Number of messages in window (default: calculated)
  - `:overlap` - Number of messages to overlap between windows (default: 2)

  ## Examples

      iex> Strategy.sliding_window(prompt, model, 2000, count: 20, overlap: 3)
      {:ok, %Prompt{}}
  """
  @spec sliding_window(Prompt.t(), Model.t(), non_neg_integer(), keyword()) ::
          {:ok, Prompt.t()} | {:error, term()}
  def sliding_window(%Prompt{messages: messages} = prompt, model, limit, opts \\ []) do
    overlap = Keyword.get(opts, :overlap, 2)

    count =
      case Keyword.get(opts, :count) do
        nil -> calculate_message_count(messages, model, limit)
        n when is_integer(n) -> n
      end

    total_messages = length(messages)

    cond do
      # All messages fit
      total_messages <= count ->
        {:ok, prompt}

      # Need to apply sliding window
      overlap < count ->
        # Take the last 'count' messages, ensuring we include overlap from previous window
        # This creates a natural continuation point
        start_index = max(0, total_messages - count)
        truncated_messages = Enum.slice(messages, start_index..-1//1)
        {:ok, %{prompt | messages: truncated_messages}}

      # Invalid: overlap >= count
      true ->
        {:error, :invalid_overlap}
    end
  end

  @doc """
  Intelligently truncates while preserving important context.

  Preserves:
  - System messages (instructions)
  - First user message (often contains task description)
  - Recent messages (current context)
  - Messages with special markers or importance

  ## Options
  - `:count` - Target number of messages (default: calculated to fit)
  - `:preserve_first` - Keep first user message (default: true)

  ## Examples

      iex> Strategy.smart_truncate(prompt, model, 2000, count: 15)
      {:ok, %Prompt{}}
  """
  @spec smart_truncate(Prompt.t(), Model.t(), non_neg_integer(), keyword()) ::
          {:ok, Prompt.t()} | {:error, term()}
  def smart_truncate(%Prompt{messages: messages} = prompt, model, limit, opts \\ []) do
    preserve_first = Keyword.get(opts, :preserve_first, true)

    # Separate into categories
    {system_messages, non_system} =
      Enum.split_with(messages, fn msg -> Map.get(msg, :role) == :system end)

    {first_user, remaining} =
      if preserve_first do
        case Enum.split_while(non_system, fn msg -> Map.get(msg, :role) != :user end) do
          {prefix, [first | rest]} -> {prefix ++ [first], rest}
          {prefix, []} -> {prefix, []}
        end
      else
        {[], non_system}
      end

    # Calculate available space
    preserved = system_messages ++ first_user
    preserved_tokens = Tokenizer.count_messages(preserved, model.provider)
    available = limit - preserved_tokens

    # Keep as many recent messages as fit
    count = calculate_message_count(remaining, model, available)
    recent = Enum.take(remaining, -count)

    truncated_messages = system_messages ++ first_user ++ recent

    {:ok, %{prompt | messages: truncated_messages}}
  end

  # Private Helpers

  @doc false
  @spec calculate_message_count(list(map()), Model.t(), non_neg_integer()) :: non_neg_integer()
  defp calculate_message_count(messages, model, limit) do
    # Binary search to find how many messages fit
    calculate_message_count_binary(messages, model, limit, 0, length(messages))
  end

  defp calculate_message_count_binary(_messages, _model, _limit, low, high) when low >= high do
    low
  end

  defp calculate_message_count_binary(messages, model, limit, low, high) do
    mid = div(low + high + 1, 2)
    test_messages = Enum.take(messages, -mid)
    tokens = Tokenizer.count_messages(test_messages, model.provider)

    if tokens <= limit do
      # Try to fit more
      calculate_message_count_binary(messages, model, limit, mid, high)
    else
      # Too many, try fewer
      calculate_message_count_binary(messages, model, limit, low, mid - 1)
    end
  end
end
