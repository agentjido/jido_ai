defmodule Jido.Eval.LLM do
  @moduledoc """
  LLM wrapper for Jido Eval with retry policies, caching, and error normalization.

  Provides a unified interface to `Jido.AI` with evaluation-specific features:
  - Retry policies with exponential backoff and jitter
  - Response caching for deterministic testing and cost control
  - Error normalization and propagation
  - Support for all Jido.AI model specification formats

  ## Examples

      # Simple text generation with retries
      {:ok, response} = Jido.Eval.LLM.generate_text(
        "openai:gpt-4o",
        "Evaluate this response: Hello world"
      )

      # Structured generation with custom retry policy
      schema = [score: [type: :float, required: true]]
      policy = %Jido.Eval.RetryPolicy{max_retries: 5, base_delay: 2000}

      {:ok, result} = Jido.Eval.LLM.generate_object(
        "openai:gpt-4o",
        "Rate this response from 0-1",
        schema,
        retry_policy: policy
      )

      # With caching enabled
      {:ok, cached_result} = Jido.Eval.LLM.generate_text(
        "openai:gpt-4o",
        "Same prompt",
        cache: true
      )
  """

  alias Jido.Eval.RetryPolicy
  alias Jido.AI.Error

  @type model_spec :: Jido.AI.Model.t() | {atom(), keyword()} | String.t()
  @type prompt :: String.t() | [Jido.AI.Message.t()]
  @type cache_key :: String.t()

  @default_retry_policy %RetryPolicy{}

  # ===========================================================================
  # Public API
  # ===========================================================================

  @doc """
  Generate text using an AI model with retry and caching support.

  ## Options

    * `:retry_policy` - Retry policy configuration (default: `%RetryPolicy{}`)
    * `:cache` - Enable response caching (default: `false`)
    * `:cache_ttl` - Cache TTL in milliseconds (default: `300_000` - 5 minutes)
    * All other options are passed through to `Jido.AI.generate_text/3`

  ## Examples

      {:ok, response} = Jido.Eval.LLM.generate_text("openai:gpt-4o", "Hello")

      # With custom retry policy
      policy = %RetryPolicy{max_retries: 5, base_delay: 1500}
      {:ok, response} = Jido.Eval.LLM.generate_text(
        "openai:gpt-4o", 
        "Hello", 
        retry_policy: policy
      )

      # With caching
      {:ok, response} = Jido.Eval.LLM.generate_text(
        "openai:gpt-4o", 
        "Hello", 
        cache: true, 
        cache_ttl: 600_000
      )
  """
  @spec generate_text(model_spec(), prompt(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def generate_text(model_spec, prompt, opts \\ []) do
    {retry_policy, cache_opts, ai_opts} = extract_options(opts)

    operation = fn -> Jido.AI.generate_text(model_spec, prompt, ai_opts) end
    cache_key = build_cache_key(model_spec, prompt, ai_opts)

    with_cache_and_retry(operation, cache_key, cache_opts, retry_policy)
  end

  @doc """
  Generate structured data using an AI model with retry and caching support.

  ## Options

    * `:retry_policy` - Retry policy configuration (default: `%RetryPolicy{}`)
    * `:cache` - Enable response caching (default: `false`)
    * `:cache_ttl` - Cache TTL in milliseconds (default: `300_000` - 5 minutes)
    * All other options are passed through to `Jido.AI.generate_object/4`

  ## Examples

      schema = [score: [type: :float, required: true]]
      {:ok, result} = Jido.Eval.LLM.generate_object(
        "openai:gpt-4o", 
        "Rate this", 
        schema
      )

      # With retry policy and caching
      policy = %RetryPolicy{max_retries: 3}
      {:ok, result} = Jido.Eval.LLM.generate_object(
        "openai:gpt-4o", 
        "Rate this", 
        schema,
        retry_policy: policy,
        cache: true
      )
  """
  @spec generate_object(model_spec(), prompt(), keyword(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def generate_object(model_spec, prompt, schema, opts \\ []) do
    {retry_policy, cache_opts, ai_opts} = extract_options(opts)

    operation = fn -> Jido.AI.generate_object(model_spec, prompt, schema, ai_opts) end
    cache_key = build_cache_key(model_spec, {prompt, schema}, ai_opts)

    with_cache_and_retry(operation, cache_key, cache_opts, retry_policy)
  end

  @doc """
  Clear all cached responses.

  Useful for testing or when you want to force fresh API calls.

  ## Examples

      Jido.Eval.LLM.clear_cache()
      #=> :ok
  """
  @spec clear_cache() :: :ok
  def clear_cache do
    case :ets.whereis(__MODULE__) do
      :undefined -> :ok
      _ -> :ets.delete_all_objects(__MODULE__)
    end

    :ok
  end

  # ===========================================================================
  # Private Implementation
  # ===========================================================================

  defp extract_options(opts) do
    retry_policy = Keyword.get(opts, :retry_policy, @default_retry_policy)

    cache_opts = %{
      enabled: Keyword.get(opts, :cache, false),
      ttl: Keyword.get(opts, :cache_ttl, 300_000)
    }

    ai_opts = Keyword.drop(opts, [:retry_policy, :cache, :cache_ttl])

    {retry_policy, cache_opts, ai_opts}
  end

  defp with_cache_and_retry(operation, cache_key, cache_opts, retry_policy) do
    if cache_opts.enabled do
      case get_cached(cache_key) do
        {:ok, result} -> {:ok, result}
        :miss -> execute_with_retry_and_cache(operation, cache_key, cache_opts, retry_policy)
      end
    else
      execute_with_retry(operation, retry_policy)
    end
  end

  defp execute_with_retry_and_cache(operation, cache_key, cache_opts, retry_policy) do
    case execute_with_retry(operation, retry_policy) do
      {:ok, result} ->
        cache_result(cache_key, result, cache_opts.ttl)
        {:ok, result}

      {:error, _} = error ->
        error
    end
  end

  defp execute_with_retry(operation, retry_policy, attempt \\ 1) do
    case operation.() do
      {:ok, result} ->
        {:ok, result}

      {:error, error} ->
        if should_retry?(error, attempt, retry_policy) do
          delay = calculate_delay(attempt, retry_policy)
          Process.sleep(delay)
          execute_with_retry(operation, retry_policy, attempt + 1)
        else
          {:error, normalize_error(error)}
        end
    end
  end

  defp should_retry?(error, attempt, retry_policy) do
    attempt <= retry_policy.max_retries and error_retryable?(error, retry_policy)
  end

  defp error_retryable?(error, retry_policy) do
    error_type = classify_error(error)
    error_type in retry_policy.retryable_errors
  end

  defp classify_error(%Error.API.Request{status: 429}), do: :rate_limit
  defp classify_error(%Error.API.Request{status: status}) when status >= 500, do: :server_error

  defp classify_error(%Error.API.Request{reason: reason}) when is_atom(reason) do
    case reason do
      :timeout -> :timeout
      :connect_timeout -> :timeout
      :checkout_timeout -> :timeout
      _ -> :api_error
    end
  end

  defp classify_error(%Error.API.Request{}), do: :api_error
  defp classify_error(_), do: :unknown

  defp calculate_delay(attempt, retry_policy) do
    base_delay = retry_policy.base_delay * :math.pow(2, attempt - 1)
    capped_delay = min(base_delay, retry_policy.max_delay)

    if retry_policy.jitter do
      jitter = :rand.uniform() * capped_delay * 0.1
      round(capped_delay + jitter)
    else
      round(capped_delay)
    end
  end

  defp normalize_error(error) do
    # Ensure all errors follow a consistent format
    case error do
      %Error.API.Request{} = api_error -> api_error
      %{__exception__: true} = exception -> Error.Unknown.Unknown.exception(error: exception)
      other -> Error.Unknown.Unknown.exception(error: other)
    end
  end

  # ===========================================================================
  # Caching Implementation
  # ===========================================================================

  defp ensure_cache_table do
    unless :ets.whereis(__MODULE__) != :undefined do
      :ets.new(__MODULE__, [:set, :public, :named_table])
    end

    :ok
  end

  defp build_cache_key(model_spec, prompt, opts) do
    # Create deterministic cache key from model spec, prompt, and relevant options
    key_data = %{
      model: normalize_model_spec(model_spec),
      prompt: prompt,
      opts: Enum.sort(opts)
    }

    :crypto.hash(:sha256, :erlang.term_to_binary(key_data))
    |> Base.encode16(case: :lower)
  end

  defp normalize_model_spec(model_spec) when is_binary(model_spec), do: model_spec

  defp normalize_model_spec({provider, opts}) when is_atom(provider),
    do: {provider, Enum.sort(opts)}

  defp normalize_model_spec(%Jido.AI.Model{} = model), do: Map.take(model, [:provider, :model])

  defp get_cached(cache_key) do
    ensure_cache_table()

    case :ets.lookup(__MODULE__, cache_key) do
      [{^cache_key, result, expires_at}] ->
        if System.monotonic_time(:millisecond) < expires_at do
          {:ok, result}
        else
          :ets.delete(__MODULE__, cache_key)
          :miss
        end

      [] ->
        :miss
    end
  end

  defp cache_result(cache_key, result, ttl) do
    ensure_cache_table()
    expires_at = System.monotonic_time(:millisecond) + ttl
    :ets.insert(__MODULE__, {cache_key, result, expires_at})
    :ok
  end
end
