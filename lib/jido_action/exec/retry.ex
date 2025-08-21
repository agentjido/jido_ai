defmodule Jido.Exec.Retry do
  @moduledoc """
  Retry logic and backoff calculations for action execution.

  This module centralizes retry behavior, including:
  - Exponential backoff calculations with capping
  - Retry decision logic based on error type and attempt count
  - Retry option processing and validation
  """

  alias Jido.Exec.Telemetry

  require Logger

  @doc """
  Calculate exponential backoff time for a retry attempt.

  Uses exponential backoff with a maximum cap of 30 seconds.

  ## Parameters

  - `retry_count`: The current retry attempt number (0-based)
  - `initial_backoff`: The initial backoff time in milliseconds

  ## Returns

  The calculated backoff time in milliseconds, capped at 30,000ms.

  ## Examples

      iex> Jido.Exec.Retry.calculate_backoff(0, 250)
      250
      
      iex> Jido.Exec.Retry.calculate_backoff(1, 250)
      500
      
      iex> Jido.Exec.Retry.calculate_backoff(2, 250)
      1000
  """
  @spec calculate_backoff(non_neg_integer(), non_neg_integer()) :: non_neg_integer()
  def calculate_backoff(retry_count, initial_backoff) do
    (initial_backoff * :math.pow(2, retry_count))
    |> round()
    |> min(30_000)
  end

  @doc """
  Determine if an action should be retried based on the error and attempt count.

  ## Parameters

  - `error`: The error that occurred during execution
  - `retry_count`: The current retry attempt number
  - `max_retries`: The maximum number of retries allowed
  - `opts`: Additional options (currently unused but reserved for future use)

  ## Returns

  `true` if the action should be retried, `false` otherwise.

  ## Examples

      iex> Jido.Exec.Retry.should_retry?({:error, "network error"}, 0, 3, [])
      true
      
      iex> Jido.Exec.Retry.should_retry?({:error, "network error"}, 3, 3, [])
      false
  """
  @spec should_retry?(any(), non_neg_integer(), non_neg_integer(), keyword()) :: boolean()
  def should_retry?(_error, retry_count, max_retries, _opts) do
    retry_count < max_retries
  end

  @doc """
  Execute a retry with proper backoff and logging.

  This function handles the retry orchestration including:
  - Calculating the backoff time
  - Logging the retry attempt
  - Sleeping for the backoff period

  ## Parameters

  - `action`: The action module being retried
  - `retry_count`: The current retry attempt number
  - `max_retries`: The maximum number of retries allowed
  - `initial_backoff`: The initial backoff time in milliseconds
  - `opts`: Options for logging and other behavior
  - `retry_fn`: Function to call for the actual retry attempt

  ## Returns

  The result of calling `retry_fn`.
  """
  @spec execute_retry(
          module(),
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer(),
          keyword(),
          function()
        ) :: any()
  def execute_retry(action, retry_count, max_retries, initial_backoff, opts, retry_fn) do
    backoff = calculate_backoff(retry_count, initial_backoff)

    Telemetry.cond_log_retry(
      Keyword.get(opts, :log_level, :info),
      action,
      retry_count,
      max_retries,
      backoff
    )

    :timer.sleep(backoff)
    retry_fn.()
  end

  @doc """
  Get default retry configuration values.

  ## Returns

  A keyword list with default retry configuration:
  - `:max_retries`: Default maximum retry attempts
  - `:backoff`: Default initial backoff time in milliseconds
  """
  @spec default_retry_config() :: keyword()
  def default_retry_config do
    [
      max_retries: Application.get_env(:jido_action, :default_max_retries, 1),
      backoff: Application.get_env(:jido_action, :default_backoff, 250)
    ]
  end

  @doc """
  Extract and validate retry options from the provided opts.

  ## Parameters

  - `opts`: The options keyword list to extract retry config from

  ## Returns

  A keyword list with validated retry configuration values.
  """
  @spec extract_retry_opts(keyword()) :: keyword()
  def extract_retry_opts(opts) do
    defaults = default_retry_config()

    [
      max_retries: Keyword.get(opts, :max_retries, defaults[:max_retries]),
      backoff: Keyword.get(opts, :backoff, defaults[:backoff])
    ]
  end
end
