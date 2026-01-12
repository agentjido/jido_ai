defmodule Jido.AI.Accuracy.RateLimiter do
  @moduledoc """
  Simple rate limiter for LLM API calls.

  Uses ETS to track request counts per time window. This helps prevent
  excessive API calls and manage costs.

  ## Usage

      # Check if a request is allowed (default: 10 requests per 60 seconds)
      case RateLimiter.allow_request(:my_verifier) do
        :ok -> # Make the request
        {:error, :rate_limited} -> # Handle rate limit
      end

      # Configure custom limits
      RateLimiter.configure(:my_verifier, max_requests: 100, window_ms: 60_000)

      # Reset rate limit state
      RateLimiter.reset(:my_verifier)

  """

  use GenServer

  @table_name :jido_ai_rate_limiter
  @default_max_requests 10
  @default_window_ms 60_000

  # Client API

  @doc """
  Checks if a request is allowed for the given key.

  ## Parameters

  - `key` - Identifier for the rate limit category (e.g., verifier name)
  - `opts` - Optional overrides:
    - `:max_requests` - Max requests in window (default: from config or 10)
    - `:window_ms` - Time window in ms (default: from config or 60000)

  ## Returns

  - `:ok` - Request is allowed
  - `{:error, :rate_limited}` - Rate limit exceeded
  - `{:error, reason}` - Other error

  ## Examples

      iex> RateLimiter.allow_request(:test)
      :ok

  """
  @spec allow_request(atom(), keyword()) :: :ok | {:error, term()}
  def allow_request(key, opts \\ []) do
    max_requests = Keyword.get(opts, :max_requests, get_max_requests(key))
    window_ms = Keyword.get(opts, :window_ms, get_window_ms(key))

    case GenServer.call(__MODULE__, {:check_rate, key, max_requests, window_ms}) do
      true -> :ok
      false -> {:error, :rate_limited}
    end
  catch
    :exit, {:noproc, _} ->
      # GenServer not started, allow request
      :ok
  end

  @doc """
  Configures rate limits for a key.

  ## Parameters

  - `key` - Identifier for the rate limit category
  - `opts` - Configuration options:
    - `:max_requests` - Max requests in time window
    - `:window_ms` - Time window in milliseconds

  """
  @spec configure(atom(), keyword()) :: :ok
  def configure(key, opts) do
    GenServer.call(__MODULE__, {:configure, key, opts})
  catch
    :exit, {:noproc, _} ->
      # GenServer not started, store config in ETS directly
      store_config(key, opts)
      :ok
  end

  @doc """
  Resets the rate limit counter for a key.

  ## Parameters

  - `key` - Identifier for the rate limit category

  """
  @spec reset(atom()) :: :ok
  def reset(key) do
    GenServer.call(__MODULE__, {:reset, key})
  catch
    :exit, {:noproc, _} ->
      # GenServer not started, reset directly
      ets_delete(:jido_ai_rate_limiter, {key, :counter})
      ets_delete(:jido_ai_rate_limiter, {key, :window_start})
      :ok
  end

  @doc """
  Gets the current rate limit status for a key.

  ## Returns

  - `%{remaining: integer(), reset_at: integer()}` - Current status

  """
  @spec status(atom()) :: map()
  def status(key) do
    GenServer.call(__MODULE__, {:status, key})
  catch
    :exit, {:noproc, _} ->
      %{remaining: get_max_requests(key), reset_at: System.monotonic_time(:millisecond) + get_window_ms(key)}
  end

  # Server callbacks

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    # Create ETS table for rate limit tracking
    table = :ets.new(@table_name, [:named_table, :public, read_concurrency: true])

    # Create configuration table
    :ets.new(:jido_ai_rate_limiter_config, [:named_table, :public])

    {:ok, %{table: table}}
  end

  @impl true
  def handle_call({:check_rate, key, max_requests, window_ms}, _from, state) do
    now = System.monotonic_time(:millisecond)

    # Get or initialize window start time
    window_start =
      case :ets.lookup(@table_name, {key, :window_start}) do
        [{_, start}] -> start
        [] ->
          :ets.insert(@table_name, {{key, :window_start}, now})
          now
      end

    # Get current request count
    current_count =
      case :ets.lookup(@table_name, {key, :counter}) do
        [{_, count}] -> count
        [] -> 0
      end

    # Check if window has expired
    if now - window_start >= window_ms do
      # Reset window
      :ets.insert(@table_name, {{key, :window_start}, now})
      :ets.insert(@table_name, {{key, :counter}, 1})
      {:reply, true, state}
    else
      # Check if rate limit exceeded
      if current_count < max_requests do
        :ets.insert(@table_name, {{key, :counter}, current_count + 1})
        {:reply, true, state}
      else
        {:reply, false, state}
      end
    end
  end

  def handle_call({:configure, key, opts}, _from, state) do
    store_config(key, opts)
    {:reply, :ok, state}
  end

  def handle_call({:reset, key}, _from, state) do
    ets_delete(@table_name, {key, :counter})
    ets_delete(@table_name, {key, :window_start})
    {:reply, :ok, state}
  end

  def handle_call({:status, key}, _from, state) do
    max_requests = get_max_requests(key)
    window_ms = get_window_ms(key)

    current_count =
      case :ets.lookup(@table_name, {key, :counter}) do
        [{_, count}] -> count
        [] -> 0
      end

    window_start =
      case :ets.lookup(@table_name, {key, :window_start}) do
        [{_, start}] -> start
        [] -> System.monotonic_time(:millisecond)
      end

    reset_at = window_start + window_ms
    remaining = max(0, max_requests - current_count)

    {:reply, %{remaining: remaining, reset_at: reset_at}, state}
  end

  # Private functions

  defp store_config(key, opts) do
    max_requests = Keyword.get(opts, :max_requests)
    window_ms = Keyword.get(opts, :window_ms)

    config = %{}
    config = if max_requests, do: Map.put(config, :max_requests, max_requests), else: config
    config = if window_ms, do: Map.put(config, :window_ms, window_ms), else: config

    if map_size(config) > 0 do
      :ets.insert(:jido_ai_rate_limiter_config, {key, config})
    end

    :ok
  end

  defp get_max_requests(key) do
    case :ets.lookup(:jido_ai_rate_limiter_config, key) do
      [{_, %{max_requests: max}}] -> max
      _ -> Application.get_env(:jido_ai, :rate_limit_max_requests, @default_max_requests)
    end
  end

  defp get_window_ms(key) do
    case :ets.lookup(:jido_ai_rate_limiter_config, key) do
      [{_, %{window_ms: window}}] -> window
      _ -> Application.get_env(:jido_ai, :rate_limit_window_ms, @default_window_ms)
    end
  end

  defp ets_delete(table, key) do
    try do
      :ets.delete(table, key)
    rescue
      ArgumentError -> :ok
    end
  end
end
