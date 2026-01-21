defmodule Jido.AI.Model.Registry.Optimizer do
  @moduledoc """
  Provider-specific configuration and optimization settings.

  This module defines provider-specific timeout values, retry strategies, and
  connection pool settings optimized for each provider's characteristics.

  ## Provider Categories

  - **Fast providers** (OpenAI, Anthropic): Low latency, aggressive timeouts
  - **Medium providers** (Google, Mistral): Moderate latency, balanced timeouts
  - **Slow providers** (Regional, self-hosted): Higher latency, generous timeouts

  ## Usage

      config = Optimizer.get_provider_config(:openai)
      # => %{connect_timeout: 5_000, receive_timeout: 10_000, ...}

      req_opts = Optimizer.build_req_options(:anthropic)
      # => [connect_timeout: 5_000, max_retries: 2, ...]
  """

  @type provider_config :: %{
          connect_timeout: non_neg_integer(),
          receive_timeout: non_neg_integer(),
          pool_timeout: non_neg_integer(),
          max_retries: non_neg_integer(),
          retry_delay_base: non_neg_integer()
        }

  # Fast providers: Low latency, quick responses
  @fast_providers [
    :openai,
    :anthropic,
    :groq,
    :together_ai,
    :fireworks_ai
  ]

  @fast_config %{
    connect_timeout: 5_000,
    receive_timeout: 10_000,
    pool_timeout: 3_000,
    max_retries: 2,
    retry_delay_base: 1_000
  }

  # Medium providers: Moderate latency
  @medium_providers [
    :google,
    :cohere,
    :mistral,
    :azure_openai,
    :perplexity,
    :replicate
  ]

  @medium_config %{
    connect_timeout: 10_000,
    receive_timeout: 15_000,
    pool_timeout: 5_000,
    max_retries: 3,
    retry_delay_base: 1_500
  }

  # Slow providers: Higher latency (regional, self-hosted, specialized)
  @slow_providers [
    :amazon_bedrock,
    :alibaba_cloud,
    :local,
    :ollama,
    :lmstudio
  ]

  @slow_config %{
    connect_timeout: 30_000,
    receive_timeout: 30_000,
    pool_timeout: 5_000,
    max_retries: 4,
    retry_delay_base: 2_000
  }

  # Default configuration for unknown providers
  @default_config %{
    connect_timeout: 15_000,
    receive_timeout: 20_000,
    pool_timeout: 5_000,
    max_retries: 3,
    retry_delay_base: 1_500
  }

  @doc """
  Returns configuration for a specific provider.

  ## Examples

      iex> Optimizer.get_provider_config(:openai)
      %{
        connect_timeout: 5_000,
        receive_timeout: 10_000,
        pool_timeout: 3_000,
        max_retries: 2,
        retry_delay_base: 1_000
      }

      iex> Optimizer.get_provider_config(:unknown_provider)
      %{connect_timeout: 15_000, ...}  # Returns default config
  """
  @spec get_provider_config(atom()) :: provider_config()
  def get_provider_config(provider_id) when is_atom(provider_id) do
    cond do
      provider_id in @fast_providers -> @fast_config
      provider_id in @medium_providers -> @medium_config
      provider_id in @slow_providers -> @slow_config
      true -> @default_config
    end
  end

  @doc """
  Builds Req options for a provider based on its configuration.

  ## Examples

      opts = Optimizer.build_req_options(:openai)
      # Can be passed to Req.request/1 or Req.new/1
  """
  @spec build_req_options(atom()) :: keyword()
  def build_req_options(provider_id) when is_atom(provider_id) do
    config = get_provider_config(provider_id)

    [
      connect_options: [
        timeout: config.connect_timeout,
        protocols: [:http1, :http2],
        pool_timeout: config.pool_timeout
      ],
      receive_timeout: config.receive_timeout,
      retry: &retry_strategy/2,
      max_retries: config.max_retries,
      retry_delay: fn count -> exponential_backoff(count, config.retry_delay_base) end,
      retry_log_level: :info,
      compressed: true,
      decode_json: [
        keys: :atoms!,
        strings: :copy
      ]
    ]
  end

  @doc """
  Determines if a request should be retried based on response or error.

  Retries on:
  - HTTP 408 (Request Timeout)
  - HTTP 429 (Too Many Requests)
  - HTTP 5xx (Server Errors)
  - Network errors (timeout, connection refused)

  ## Examples

      retry_strategy(req, %{status: 503})  # => true (server error)
      retry_strategy(req, %{status: 200})  # => false (success)
  """
  @spec retry_strategy(Req.Request.t(), Req.Response.t() | Exception.t()) :: boolean()
  def retry_strategy(_req, response_or_error) do
    case response_or_error do
      # HTTP errors worth retrying
      %{status: status} when status in [408, 429, 500, 502, 503, 504] ->
        true

      # Network/transport errors
      %Req.TransportError{reason: reason} when reason in [:timeout, :econnrefused, :closed] ->
        true

      # Don't retry other cases
      _ ->
        false
    end
  end

  @doc """
  Calculates exponential backoff delay with jitter.

  ## Examples

      exponential_backoff(0, 1000)  # => ~1000-1500ms
      exponential_backoff(1, 1000)  # => ~2000-2500ms
      exponential_backoff(2, 1000)  # => ~4000-4500ms
  """
  @spec exponential_backoff(non_neg_integer(), non_neg_integer()) :: non_neg_integer()
  def exponential_backoff(retry_count, base_delay \\ 1_000) do
    # Calculate: base_delay * 2^retry_count
    base = base_delay * :math.pow(2, retry_count)

    # Add jitter (0-500ms) to prevent thundering herd
    jitter = :rand.uniform(500)

    trunc(base + jitter)
  end

  @doc """
  Returns the provider category for a given provider.

  ## Examples

      iex> Optimizer.get_provider_category(:openai)
      :fast

      iex> Optimizer.get_provider_category(:google)
      :medium
  """
  @spec get_provider_category(atom()) :: :fast | :medium | :slow | :default
  def get_provider_category(provider_id) when is_atom(provider_id) do
    cond do
      provider_id in @fast_providers -> :fast
      provider_id in @medium_providers -> :medium
      provider_id in @slow_providers -> :slow
      true -> :default
    end
  end

  @doc """
  Lists all provider IDs in a given category.

  ## Examples

      iex> Optimizer.providers_in_category(:fast)
      [:openai, :anthropic, :groq, :together_ai, :fireworks_ai]
  """
  @spec providers_in_category(:fast | :medium | :slow) :: list(atom())
  def providers_in_category(:fast), do: @fast_providers
  def providers_in_category(:medium), do: @medium_providers
  def providers_in_category(:slow), do: @slow_providers

  @doc """
  Returns all provider configurations as a map.

  Useful for debugging and monitoring.
  """
  @spec all_configs() :: map()
  def all_configs do
    %{
      fast: %{providers: @fast_providers, config: @fast_config},
      medium: %{providers: @medium_providers, config: @medium_config},
      slow: %{providers: @slow_providers, config: @slow_config},
      default: %{config: @default_config}
    }
  end
end
