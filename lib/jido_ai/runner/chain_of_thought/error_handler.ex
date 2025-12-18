defmodule Jido.AI.Runner.ChainOfThought.ErrorHandler do
  @moduledoc """
  Comprehensive error handling for Chain-of-Thought reasoning operations.

  Provides structured error types, retry logic with exponential backoff, recovery strategies,
  and detailed error logging with context for debugging and monitoring.

  ## Error Categories

  - **LLM Errors**: API failures, timeouts, rate limits, parsing failures
  - **Execution Errors**: Action failures, validation failures, context errors
  - **Configuration Errors**: Invalid config, missing required parameters

  ## Recovery Strategies

  - **Retry**: Attempt operation again with exponential backoff
  - **Fallback to Simpler Mode**: Use simpler reasoning when complex reasoning fails
  - **Fallback to Direct Execution**: Use Simple runner when reasoning fails entirely
  - **Skip and Continue**: Skip failed step and continue with remaining steps
  - **Fail Fast**: Return error immediately without recovery

  ## Usage

      alias Jido.AI.Runner.ChainOfThought.ErrorHandler

      # Wrap operation with retry
      ErrorHandler.with_retry(fn ->
        call_llm(prompt, model)
      end, max_retries: 3)

      # Handle error with recovery
      ErrorHandler.handle_error(error, context, strategy: :fallback)

      # Log error with full context
      ErrorHandler.log_error(error, operation: "reasoning_generation", step: 1)
  """

  require Logger
  use TypedStruct

  alias Jido.AI.Runner.ChainOfThought.OutcomeValidator

  # Error Types

  typedstruct module: Error do
    @moduledoc """
    Structured error with category, reason, context, and recovery information.
    """
    field(:category, atom(), enforce: true)
    field(:reason, term(), enforce: true)
    field(:context, map(), default: %{})
    field(:timestamp, DateTime.t(), enforce: true)
    field(:recoverable?, boolean(), default: true)
    field(:recovery_attempted?, boolean(), default: false)
    field(:recovery_strategy, atom() | nil, default: nil)
    field(:original_error, term() | nil, default: nil)
  end

  typedstruct module: RetryConfig do
    @moduledoc """
    Configuration for retry behavior with exponential backoff.
    """
    field(:max_retries, non_neg_integer(), default: 3)
    field(:initial_delay_ms, pos_integer(), default: 1000)
    field(:max_delay_ms, pos_integer(), default: 30_000)
    field(:backoff_factor, float(), default: 2.0)
    field(:jitter?, boolean(), default: true)
  end

  # Error Categories
  @llm_errors [:api_error, :timeout, :rate_limit, :parsing_error, :invalid_response]
  @execution_errors [:action_error, :validation_error, :context_error, :unexpected_outcome]
  @config_errors [:invalid_config, :missing_parameter, :invalid_mode]

  @type error_category :: :llm_error | :execution_error | :config_error | :unknown_error
  @type recovery_strategy ::
          :retry | :fallback_simpler | :fallback_direct | :skip_continue | :fail_fast

  # Public API

  @doc """
  Wraps an operation with retry logic using exponential backoff.

  ## Options

  - `:max_retries` - Maximum number of retry attempts (default: 3)
  - `:initial_delay_ms` - Initial delay between retries in milliseconds (default: 1000)
  - `:max_delay_ms` - Maximum delay between retries in milliseconds (default: 30000)
  - `:backoff_factor` - Multiplier for exponential backoff (default: 2.0)
  - `:jitter?` - Add random jitter to delay (default: true)

  ## Examples

      with_retry(fn -> call_api() end, max_retries: 3)
      with_retry(fn -> parse_response(data) end, initial_delay_ms: 500)
  """
  @spec with_retry(function(), keyword()) :: {:ok, term()} | {:error, Error.t()}
  def with_retry(operation, opts \\ []) do
    config = struct(RetryConfig, opts)
    do_retry(operation, config, 0, nil)
  end

  @doc """
  Categorizes an error into one of the standard error categories.

  ## Examples

      categorize_error({:error, :timeout})
      #=> :llm_error

      categorize_error({:error, :invalid_action})
      #=> :execution_error
  """
  @spec categorize_error(term()) :: error_category()
  def categorize_error({:error, reason}) when is_atom(reason) do
    cond do
      reason in @llm_errors -> :llm_error
      reason in @execution_errors -> :execution_error
      reason in @config_errors -> :config_error
      true -> :unknown_error
    end
  end

  def categorize_error({:error, %{__exception__: true} = _exception}) do
    # Generic error categorization for exceptions
    # Most LLM-related exceptions will be network or API errors
    :llm_error
  end

  def categorize_error(_), do: :unknown_error

  @doc """
  Creates a structured error with full context information.

  ## Examples

      create_error(:llm_error, :timeout,
        operation: "reasoning_generation",
        step: 1,
        elapsed_ms: 5000
      )
  """
  @spec create_error(error_category(), term(), keyword()) :: Error.t()
  def create_error(category, reason, context_opts \\ []) do
    %Error{
      category: category,
      reason: reason,
      context: Map.new(context_opts),
      timestamp: DateTime.utc_now(),
      recoverable?: recoverable?(category, reason),
      original_error: Keyword.get(context_opts, :original_error)
    }
  end

  @doc """
  Handles an error with the specified recovery strategy.

  Returns the result of the recovery operation or the original error if recovery fails.

  ## Options

  - `:strategy` - Recovery strategy to use (default: auto-selected based on error)
  - `:fallback_fn` - Function to call for fallback (required for fallback strategies)
  - `:agent` - Agent context for recovery operations
  - `:config` - Runner configuration

  ## Examples

      handle_error(error, %{operation: "reasoning"},
        strategy: :fallback_direct,
        fallback_fn: fn -> Simple.run(agent) end
      )
  """
  @spec handle_error(Error.t() | term(), map(), keyword()) ::
          {:ok, term()} | {:error, Error.t()}
  def handle_error(error, context, opts \\ [])

  def handle_error(%Error{} = error, context, opts) do
    strategy = Keyword.get(opts, :strategy, select_recovery_strategy(error))

    log_error_with_recovery(error, context, strategy)

    case strategy do
      :retry ->
        handle_retry_recovery(error, context, opts)

      :fallback_simpler ->
        handle_fallback_simpler(error, context, opts)

      :fallback_direct ->
        handle_fallback_direct(error, context, opts)

      :skip_continue ->
        handle_skip_continue(error, context, opts)

      :fail_fast ->
        {:error, %{error | recovery_attempted?: true, recovery_strategy: :fail_fast}}
    end
  end

  def handle_error(error, context, opts) do
    category = categorize_error(error)
    structured_error = create_error(category, error, Map.to_list(context))
    handle_error(structured_error, context, opts)
  end

  @doc """
  Logs an error with full context information.

  ## Examples

      log_error(error, operation: "reasoning_generation", step: 1)
  """
  @spec log_error(Error.t() | term(), keyword()) :: :ok
  def log_error(error, context_opts \\ [])

  def log_error(%Error{} = error, context_opts) do
    context = Keyword.merge(Map.to_list(error.context), context_opts)

    Logger.error("""
    ChainOfThought Error:
      Category: #{error.category}
      Reason: #{format_reason(error.reason)}
      Timestamp: #{DateTime.to_iso8601(error.timestamp)}
      Recoverable: #{error.recoverable?}
      Context: #{format_context(context)}
    """)

    if error.original_error do
      Logger.error("Original error: #{inspect(error.original_error)}")
    end

    :ok
  end

  def log_error(error, context_opts) do
    Logger.error("ChainOfThought Error: #{inspect(error)}")
    Logger.error("Context: #{inspect(context_opts)}")
    :ok
  end

  @doc """
  Checks if an error is recoverable based on category and reason.

  ## Examples

      recoverable?(:llm_error, :timeout)
      #=> true

      recoverable?(:config_error, :invalid_mode)
      #=> false
  """
  @spec recoverable?(error_category(), term()) :: boolean()
  def recoverable?(:llm_error, reason) when reason in [:timeout, :rate_limit], do: true
  def recoverable?(:llm_error, :api_error), do: true
  def recoverable?(:execution_error, :unexpected_outcome), do: true
  def recoverable?(:execution_error, :action_error), do: true
  def recoverable?(:config_error, _), do: false
  def recoverable?(_, _), do: true

  @doc """
  Selects appropriate recovery strategy based on error type and context.

  ## Examples

      select_recovery_strategy(%Error{category: :llm_error, reason: :timeout})
      #=> :retry

      select_recovery_strategy(%Error{category: :execution_error, reason: :unexpected_outcome})
      #=> :skip_continue
  """
  @spec select_recovery_strategy(Error.t()) :: recovery_strategy()
  def select_recovery_strategy(%Error{category: :llm_error, reason: reason})
      when reason in [:timeout, :rate_limit] do
    :retry
  end

  def select_recovery_strategy(%Error{category: :llm_error}) do
    :fallback_direct
  end

  def select_recovery_strategy(%Error{category: :execution_error, reason: :unexpected_outcome}) do
    :skip_continue
  end

  def select_recovery_strategy(%Error{category: :execution_error}) do
    :skip_continue
  end

  def select_recovery_strategy(%Error{category: :config_error}) do
    :fail_fast
  end

  def select_recovery_strategy(_) do
    :fallback_direct
  end

  @doc """
  Handles unexpected outcomes from validation by deciding whether to continue or fail.

  Returns `:continue` if execution should continue, or `{:error, reason}` if it should stop.

  ## Examples

      handle_unexpected_outcome(validation, config)
      #=> :continue
  """
  @spec handle_unexpected_outcome(OutcomeValidator.ValidationResult.t(), map()) ::
          :continue | {:error, Error.t()}
  def handle_unexpected_outcome(validation, config) do
    error =
      create_error(:execution_error, :unexpected_outcome,
        expected: validation.expected_outcome,
        actual: validation.actual_outcome,
        confidence: validation.confidence,
        notes: validation.notes
      )

    strategy = Map.get(config, :unexpected_outcome_strategy, :skip_continue)

    case strategy do
      :skip_continue ->
        Logger.warning("""
        Unexpected outcome detected, continuing execution:
          Expected: #{validation.expected_outcome}
          Actual: #{validation.actual_outcome}
          Confidence: #{validation.confidence}
        """)

        :continue

      :fail_fast ->
        log_error(error, operation: "outcome_validation")
        {:error, error}

      _ ->
        :continue
    end
  end

  # Private Functions

  @spec do_retry(function(), RetryConfig.t(), non_neg_integer(), term() | nil) ::
          {:ok, term()} | {:error, Error.t()}
  defp do_retry(operation, config, attempt, last_error) do
    case operation.() do
      {:ok, result} ->
        if attempt > 0 do
          Logger.info("Retry successful after #{attempt} attempts")
        end

        {:ok, result}

      {:error, reason} = error ->
        if attempt < config.max_retries do
          delay = calculate_delay(attempt, config)

          Logger.warning("""
          Operation failed (attempt #{attempt + 1}/#{config.max_retries + 1}):
            Reason: #{inspect(reason)}
            Retrying in #{delay}ms...
          """)

          Process.sleep(delay)
          do_retry(operation, config, attempt + 1, error)
        else
          Logger.error("Operation failed after #{attempt + 1} attempts")

          error_struct =
            create_error(categorize_error(error), reason,
              attempts: attempt + 1,
              last_error: last_error,
              original_error: reason
            )

          {:error, error_struct}
        end
    end
  end

  @spec calculate_delay(non_neg_integer(), RetryConfig.t()) :: pos_integer()
  defp calculate_delay(attempt, config) do
    base_delay = config.initial_delay_ms * :math.pow(config.backoff_factor, attempt)
    delay = min(round(base_delay), config.max_delay_ms)

    if config.jitter? do
      jitter = :rand.uniform(round(delay * 0.1))
      delay + jitter
    else
      delay
    end
  end

  @spec handle_retry_recovery(Error.t(), map(), keyword()) :: {:ok, term()} | {:error, Error.t()}
  defp handle_retry_recovery(error, _context, opts) do
    operation = Keyword.get(opts, :retry_fn)

    if operation do
      Logger.info("Attempting retry recovery for #{error.reason}")
      with_retry(operation, Keyword.take(opts, [:max_retries, :initial_delay_ms]))
    else
      Logger.warning("Retry recovery requested but no retry_fn provided")
      {:error, %{error | recovery_attempted?: true, recovery_strategy: :retry}}
    end
  end

  @spec handle_fallback_simpler(Error.t(), map(), keyword()) ::
          {:ok, term()} | {:error, Error.t()}
  defp handle_fallback_simpler(error, _context, opts) do
    fallback_fn = Keyword.get(opts, :fallback_fn)

    if fallback_fn do
      Logger.info("Attempting fallback to simpler reasoning mode")

      case fallback_fn.() do
        {:ok, _result} = success ->
          success

        error_result ->
          Logger.error("Fallback to simpler mode failed: #{inspect(error_result)}")
          {:error, %{error | recovery_attempted?: true, recovery_strategy: :fallback_simpler}}
      end
    else
      Logger.warning("Fallback recovery requested but no fallback_fn provided")
      {:error, %{error | recovery_attempted?: true, recovery_strategy: :fallback_simpler}}
    end
  end

  @spec handle_fallback_direct(Error.t(), map(), keyword()) ::
          {:ok, term()} | {:error, Error.t()}
  defp handle_fallback_direct(error, _context, opts) do
    fallback_fn = Keyword.get(opts, :fallback_fn)

    if fallback_fn do
      Logger.info("Attempting fallback to direct execution (Simple runner)")

      case fallback_fn.() do
        {:ok, _agent, _directives} = success ->
          success

        error_result ->
          Logger.error("Fallback to direct execution failed: #{inspect(error_result)}")
          {:error, %{error | recovery_attempted?: true, recovery_strategy: :fallback_direct}}
      end
    else
      Logger.warning("Fallback recovery requested but no fallback_fn provided")
      {:error, %{error | recovery_attempted?: true, recovery_strategy: :fallback_direct}}
    end
  end

  @spec handle_skip_continue(Error.t(), map(), keyword()) :: {:ok, :skipped} | {:error, Error.t()}
  defp handle_skip_continue(_error, context, _opts) do
    step = Map.get(context, :step, "unknown")
    Logger.info("Skipping failed step #{step} and continuing execution")

    {:ok, :skipped}
  end

  @spec log_error_with_recovery(Error.t(), map(), recovery_strategy()) :: :ok
  defp log_error_with_recovery(error, context, strategy) do
    Logger.error("""
    ChainOfThought Error (Recovery: #{strategy}):
      Category: #{error.category}
      Reason: #{format_reason(error.reason)}
      Context: #{format_context(Map.to_list(context))}
      Recoverable: #{error.recoverable?}
      Recovery Strategy: #{strategy}
    """)

    :ok
  end

  @spec format_reason(term()) :: String.t()
  defp format_reason(reason) when is_atom(reason), do: to_string(reason)
  defp format_reason(reason) when is_binary(reason), do: reason
  defp format_reason(reason), do: inspect(reason)

  @spec format_context(keyword()) :: String.t()
  defp format_context([]), do: "none"

  defp format_context(context) do
    context
    |> Enum.map_join("", fn {key, value} ->
      "\n      #{key}: #{inspect(value)}"
    end)
  end
end
