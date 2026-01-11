defmodule Jido.AI.Accuracy.Config do
  @moduledoc """
  Centralized configuration constants for the accuracy improvement system.

  Provides default values and validation bounds for generators and aggregators.
  Using a single source of truth for configuration prevents drift between modules
  and makes it easier to adjust defaults globally.

  ## Configuration Values

  ### Model Configuration
  - `default_model/0` - Default model to use for generation

  ### Generation Configuration
  - `default_num_candidates/0` - Default number of candidates to generate
  - `max_num_candidates/0` - Maximum allowed candidates (DoS protection)
  - `min_num_candidates/0` - Minimum allowed candidates

  ### Temperature Configuration
  - `default_temperature_range/0` - Default temperature range for sampling
  - `max_temperature/0` - Maximum allowed temperature value
  - `min_temperature/0` - Minimum allowed temperature value

  ### Timeout Configuration
  - `default_timeout/0` - Default per-candidate timeout in milliseconds
  - `max_timeout/0` - Maximum allowed timeout (DoS protection)
  - `min_timeout/0` - Minimum allowed timeout

  ### Concurrency Configuration
  - `default_max_concurrency/0` - Default max parallel generations
  - `max_concurrency_limit/0` - Maximum allowed concurrency (DoS protection)
  - `min_concurrency/0` - Minimum allowed concurrency

  ## Examples

      iex> Jido.AI.Accuracy.Config.default_model()
      "anthropic:claude-haiku-4-5"

      iex> Jido.AI.Accuracy.Config.max_num_candidates()
      100
  """

  # Default model configuration
  @default_model "anthropic:claude-haiku-4-5"

  # Generation configuration
  @default_num_candidates 5
  @max_num_candidates 100
  @min_num_candidates 1

  # Temperature configuration
  @default_temperature_range {0.0, 1.0}
  @max_temperature 2.0
  @min_temperature 0.0

  # Timeout configuration
  @default_timeout 30_000
  @max_timeout 300_000
  @min_timeout 1_000

  # Concurrency configuration
  @default_max_concurrency 3
  @max_concurrency_limit 50
  @min_concurrency 1

  @doc """
  Returns the default model identifier.
  """
  def default_model, do: @default_model

  @doc """
  Returns the default number of candidates to generate.
  """
  def default_num_candidates, do: @default_num_candidates

  @doc """
  Returns the maximum allowed number of candidates (DoS protection).
  """
  def max_num_candidates, do: @max_num_candidates

  @doc """
  Returns the minimum allowed number of candidates.
  """
  def min_num_candidates, do: @min_num_candidates

  @doc """
  Returns the default temperature range for sampling.
  """
  def default_temperature_range, do: @default_temperature_range

  @doc """
  Returns the maximum allowed temperature value.
  """
  def max_temperature, do: @max_temperature

  @doc """
  Returns the minimum allowed temperature value.
  """
  def min_temperature, do: @min_temperature

  @doc """
  Returns the default timeout in milliseconds.
  """
  def default_timeout, do: @default_timeout

  @doc """
  Returns the maximum allowed timeout (DoS protection).
  """
  def max_timeout, do: @max_timeout

  @doc """
  Returns the minimum allowed timeout.
  """
  def min_timeout, do: @min_timeout

  @doc """
  Returns the default max concurrency for parallel generation.
  """
  def default_max_concurrency, do: @default_max_concurrency

  @doc """
  Returns the maximum allowed concurrency (DoS protection).
  """
  def max_concurrency_limit, do: @max_concurrency_limit

  @doc """
  Returns the minimum allowed concurrency.
  """
  def min_concurrency, do: @min_concurrency
end
