defmodule Jido.AI.ContextWindow do
  @moduledoc """
  Context window management for AI models.

  Provides intelligent context window detection, validation, and truncation
  for models with varying context sizes (4K to 1M+ tokens).

  ## Features

  - **Automatic detection**: Extract context limits from model metadata
  - **Token counting**: Accurate provider-specific token estimation
  - **Validation**: Check if messages fit within context windows
  - **Truncation**: Intelligent strategies (sliding window, keep recent, etc.)
  - **Optimization**: Utilities for extended context models

  ## Context Window Detection

  Context limits are automatically detected from model metadata:

      iex> {:ok, limits} = Jido.AI.ContextWindow.get_limits(model)
      iex> limits.total
      128000  # GPT-4 Turbo

  ## Validation

  Check if messages fit within the context window:

      iex> Jido.AI.ContextWindow.check_fit(prompt, model)
      {:ok, %{tokens: 245, limit: 128000, fits: true}}

      iex> Jido.AI.ContextWindow.ensure_fit!(prompt, model)
      :ok  # or raises ContextExceededError

  ## Truncation

  Automatically truncate messages to fit:

      iex> {:ok, truncated_prompt} = Jido.AI.ContextWindow.ensure_fit(
      ...>   prompt,
      ...>   model,
      ...>   strategy: :keep_recent,
      ...>   count: 10
      ...> )

  ## Strategies

  Available truncation strategies:
  - `:keep_recent` - Keep N most recent messages
  - `:keep_bookends` - Keep system message + N recent
  - `:sliding_window` - Sliding window with overlap
  - `:smart_truncate` - Preserve important context intelligently

  ## Examples

      # Get context window limits
      {:ok, limits} = ContextWindow.get_limits(model)

      # Check if prompt fits
      {:ok, info} = ContextWindow.check_fit(prompt, model)

      # Truncate to fit with strategy
      {:ok, truncated} = ContextWindow.ensure_fit(prompt, model,
        strategy: :keep_recent,
        count: 20
      )

      # Reserve space for completion
      {:ok, truncated} = ContextWindow.ensure_fit(prompt, model,
        reserve_completion: 2000,
        strategy: :keep_recent
      )
  """

  alias Jido.AI.ContextWindow.Strategy
  alias Jido.AI.{Model, Prompt, Tokenizer}

  defmodule Limits do
    @moduledoc """
    Context window limits for a model.

    ## Fields
    - `total` - Total context window size in tokens
    - `completion` - Maximum completion tokens
    - `prompt` - Maximum prompt tokens (derived)
    """
    defstruct [:total, :completion, :prompt]

    @type t :: %__MODULE__{
            total: non_neg_integer() | nil,
            completion: non_neg_integer() | nil,
            prompt: non_neg_integer() | nil
          }
  end

  defmodule ContextExceededError do
    @moduledoc """
    Raised when prompt exceeds context window and cannot be truncated.
    """
    defexception [:message, :tokens, :limit]

    @impl true
    def exception(opts) do
      tokens = Keyword.fetch!(opts, :tokens)
      limit = Keyword.fetch!(opts, :limit)

      %__MODULE__{
        message: "Prompt exceeds context window: #{tokens} tokens > #{limit} limit",
        tokens: tokens,
        limit: limit
      }
    end
  end

  @doc """
  Gets context window limits from a model.

  Extracts limits from the first endpoint in the model's metadata.
  Falls back to safe defaults if metadata unavailable.

  ## Parameters
  - `model` - Jido.AI.Model struct

  ## Returns
  - `{:ok, Limits.t()}` - Context window limits
  - `{:error, reason}` - If limits cannot be determined

  ## Examples

      iex> {:ok, limits} = ContextWindow.get_limits(model)
      iex> limits.total
      128000

      iex> limits.completion
      4096
  """
  @spec get_limits(Model.t()) :: {:ok, Limits.t()} | {:error, term()}
  def get_limits(%Model{} = model) do
    case model.endpoints do
      [endpoint | _] ->
        {:ok,
         %Limits{
           total: endpoint.context_length,
           completion: endpoint.max_completion_tokens,
           prompt: calculate_prompt_limit(endpoint)
         }}

      [] ->
        # No endpoints - use conservative defaults
        {:ok, %Limits{total: 4096, completion: 1000, prompt: 3096}}
    end
  end

  defp calculate_prompt_limit(%{context_length: total, max_completion_tokens: completion})
       when is_integer(total) and is_integer(completion) do
    total - completion
  end

  defp calculate_prompt_limit(%{context_length: total}) when is_integer(total) do
    # Reserve 25% for completion if max_completion_tokens not specified
    trunc(total * 0.75)
  end

  defp calculate_prompt_limit(_), do: 3096

  @doc """
  Counts tokens in a prompt for a specific model.

  Uses provider-specific token estimation.

  ## Parameters
  - `prompt` - Jido.AI.Prompt struct or message list
  - `model` - Jido.AI.Model struct

  ## Returns
  Estimated token count

  ## Examples

      iex> ContextWindow.count_tokens(prompt, model)
      245
  """
  @spec count_tokens(Prompt.t() | list(map()), Model.t()) :: non_neg_integer()
  def count_tokens(%Prompt{} = prompt, %Model{provider: provider}) do
    Tokenizer.count_prompt(prompt, provider)
  end

  def count_tokens(messages, %Model{provider: provider}) when is_list(messages) do
    Tokenizer.count_messages(messages, provider)
  end

  @doc """
  Checks if a prompt fits within the model's context window.

  ## Parameters
  - `prompt` - Jido.AI.Prompt struct or message list
  - `model` - Jido.AI.Model struct
  - `opts` - Options:
    - `:reserve_completion` - Tokens to reserve for completion (default: from model)

  ## Returns
  - `{:ok, info}` - Map with `:tokens`, `:limit`, `:fits`, `:available`
  - `{:error, reason}` - If limits cannot be determined

  ## Examples

      iex> {:ok, info} = ContextWindow.check_fit(prompt, model)
      iex> info
      %{tokens: 245, limit: 3096, fits: true, available: 2851}

      iex> {:ok, info} = ContextWindow.check_fit(prompt, model, reserve_completion: 2000)
      iex> info
      %{tokens: 245, limit: 2000, fits: true, available: 1755}
  """
  @spec check_fit(Prompt.t() | list(map()), Model.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def check_fit(prompt, model, opts \\ []) do
    with {:ok, limits} <- get_limits(model) do
      tokens = count_tokens(prompt, model)

      # Determine effective limit (may reserve space for completion)
      limit =
        case Keyword.get(opts, :reserve_completion) do
          nil -> limits.prompt || limits.total
          reserve when is_integer(reserve) -> (limits.total || 4096) - reserve
        end

      {:ok,
       %{
         tokens: tokens,
         limit: limit,
         fits: tokens <= limit,
         available: max(0, limit - tokens)
       }}
    end
  end

  @doc """
  Ensures a prompt fits within the model's context window.

  If the prompt doesn't fit, applies truncation strategy.

  ## Parameters
  - `prompt` - Jido.AI.Prompt struct
  - `model` - Jido.AI.Model struct
  - `opts` - Options:
    - `:strategy` - Truncation strategy (default: `:keep_recent`)
    - `:reserve_completion` - Tokens to reserve for completion
    - `:count` - Parameter for strategy (e.g., N messages to keep)
    - `:overlap` - For sliding window strategy

  ## Returns
  - `{:ok, Prompt.t()}` - Original or truncated prompt
  - `{:error, reason}` - If truncation fails

  ## Examples

      iex> {:ok, truncated} = ContextWindow.ensure_fit(prompt, model)

      iex> {:ok, truncated} = ContextWindow.ensure_fit(prompt, model,
      ...>   strategy: :keep_recent,
      ...>   count: 10
      ...> )

      iex> {:ok, truncated} = ContextWindow.ensure_fit(prompt, model,
      ...>   strategy: :sliding_window,
      ...>   count: 15,
      ...>   overlap: 3
      ...> )
  """
  @spec ensure_fit(Prompt.t(), Model.t(), keyword()) ::
          {:ok, Prompt.t()} | {:error, term()}
  def ensure_fit(%Prompt{} = prompt, model, opts \\ []) do
    # If explicit count provided, always truncate regardless of fit
    case {check_fit(prompt, model, opts), Keyword.get(opts, :count)} do
      {{:ok, %{fits: true}}, nil} ->
        {:ok, prompt}

      {{:ok, %{limit: limit}}, _} ->
        strategy = Keyword.get(opts, :strategy, :keep_recent)

        with {:ok, truncated} <- truncate(prompt, model, limit, strategy, opts),
             {:ok, %{fits: fits, tokens: tokens, limit: limit}} <-
               check_fit(truncated, model, opts) do
          if fits do
            {:ok, truncated}
          else
            {:error, {:context_exceeded, tokens, limit}}
          end
        end

      {{:error, reason}, _} ->
        {:error, reason}
    end
  end

  @doc """
  Ensures a prompt fits within the context window, raising on failure.

  ## Parameters
  Same as `ensure_fit/3`

  ## Returns
  - `Prompt.t()` - Original or truncated prompt
  - Raises `ContextExceededError` if prompt cannot be truncated to fit

  ## Examples

      iex> truncated = ContextWindow.ensure_fit!(prompt, model)

      iex> ContextWindow.ensure_fit!(huge_prompt, model)
      ** (ContextExceededError) Prompt exceeds context window: 150000 tokens > 128000 limit
  """
  @spec ensure_fit!(Prompt.t(), Model.t(), keyword()) :: Prompt.t() | no_return()
  def ensure_fit!(prompt, model, opts \\ []) do
    case ensure_fit(prompt, model, opts) do
      {:ok, truncated_prompt} ->
        truncated_prompt

      {:error, {:context_exceeded, tokens, limit}} ->
        raise ContextExceededError, tokens: tokens, limit: limit

      {:error, reason} ->
        raise "Failed to ensure fit: #{inspect(reason)}"
    end
  end

  @doc """
  Truncates a prompt to fit within a token limit using a strategy.

  ## Parameters
  - `prompt` - Jido.AI.Prompt struct
  - `model` - Jido.AI.Model struct
  - `limit` - Token limit
  - `strategy` - Truncation strategy atom
  - `opts` - Strategy-specific options

  ## Returns
  - `{:ok, Prompt.t()}` - Truncated prompt
  - `{:error, reason}` - If truncation fails

  ## Strategies

  - `:keep_recent` - Keep last N messages (opts: `:count`)
  - `:keep_bookends` - Keep system + last N messages (opts: `:count`)
  - `:sliding_window` - Sliding window with overlap (opts: `:count`, `:overlap`)
  - `:smart_truncate` - Intelligent context preservation (opts: `:count`)

  ## Examples

      iex> {:ok, truncated} = ContextWindow.truncate(prompt, model, 2000, :keep_recent, count: 10)
  """
  @spec truncate(Prompt.t(), Model.t(), non_neg_integer(), atom(), keyword()) ::
          {:ok, Prompt.t()} | {:error, term()}
  def truncate(%Prompt{} = prompt, model, limit, strategy, opts) do
    Strategy.apply(prompt, model, limit, strategy, opts)
  end

  @doc """
  Checks if a model supports extended context (> 100K tokens).

  ## Parameters
  - `model` - Jido.AI.Model struct

  ## Returns
  Boolean indicating if model has extended context support

  ## Examples

      iex> ContextWindow.extended_context?(model)
      true  # For GPT-4 Turbo, Claude 3, Gemini 1.5 Pro
  """
  @spec extended_context?(Model.t()) :: boolean()
  def extended_context?(%Model{} = model) do
    case get_limits(model) do
      {:ok, %Limits{total: total}} when is_integer(total) -> total >= 100_000
      _ -> false
    end
  end

  @doc """
  Gets the utilization percentage of the context window.

  ## Parameters
  - `prompt` - Jido.AI.Prompt struct or message list
  - `model` - Jido.AI.Model struct

  ## Returns
  - `{:ok, percentage}` - Utilization as float (0.0 to 100.0+)
  - `{:error, reason}` - If calculation fails

  ## Examples

      iex> {:ok, pct} = ContextWindow.utilization(prompt, model)
      iex> pct
      25.4
  """
  @spec utilization(Prompt.t() | list(map()), Model.t()) ::
          {:ok, float()} | {:error, term()}
  def utilization(prompt, model) do
    with {:ok, limits} <- get_limits(model) do
      tokens = count_tokens(prompt, model)
      limit = limits.prompt || limits.total || 4096

      percentage = tokens / limit * 100.0
      {:ok, Float.round(percentage, 2)}
    end
  end
end
