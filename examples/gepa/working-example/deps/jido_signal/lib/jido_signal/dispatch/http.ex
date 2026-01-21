defmodule Jido.Signal.Dispatch.Http do
  @moduledoc """
  An adapter for dispatching signals via HTTP requests using Erlang's built-in :httpc client.

  This adapter implements the `Jido.Signal.Dispatch.Adapter` behaviour and provides
  functionality to send signals as HTTP requests to specified endpoints. It uses the
  built-in :httpc client to avoid external dependencies.

  ## Configuration Options

  * `:url` - (required) The URL to send the request to
  * `:method` - (optional) HTTP method to use, one of [:post, :put, :patch], defaults to :post
  * `:headers` - (optional) List of headers to include in the request
  * `:timeout` - (optional) Request timeout in milliseconds, defaults to 5000
  * `:retry` - (optional) Retry configuration map with keys:
    * `:max_attempts` - Maximum number of retry attempts (default: 3)
    * `:base_delay` - Base delay between retries in milliseconds (default: 1000)
    * `:max_delay` - Maximum delay between retries in milliseconds (default: 5000)

  ## Examples

      # Basic POST request
      config = {:http, [
        url: "https://api.example.com/events",
      ]}

      # Custom configuration
      config = {:http, [
        url: "https://api.example.com/events",
        method: :put,
        headers: [{"content-type", "application/json"}, {"x-api-key", "secret"}],
        timeout: 10_000,
        retry: %{
          max_attempts: 5,
          base_delay: 2000,
          max_delay: 10000
        }
      ]}

  ## Error Handling

  The adapter handles these error conditions:

  * `:invalid_url` - The URL is not valid
  * `:connection_error` - Failed to establish connection
  * `:timeout` - Request timed out
  * `:retry_failed` - All retry attempts failed
  * Other HTTP status codes and errors
  """

  @behaviour Jido.Signal.Dispatch.Adapter
  require Logger

  @default_timeout 5000
  @default_method :post
  @default_retry %{
    max_attempts: 3,
    base_delay: 1000,
    max_delay: 5000
  }
  @valid_methods [:post, :put, :patch]

  @type http_method :: :post | :put | :patch
  @type header :: {String.t(), String.t()}
  @type retry_config :: %{
          max_attempts: pos_integer(),
          base_delay: pos_integer(),
          max_delay: pos_integer()
        }
  @type delivery_opts :: [
          url: String.t(),
          method: http_method(),
          headers: [header()],
          timeout: pos_integer(),
          retry: retry_config()
        ]
  @type delivery_error ::
          :invalid_url
          | :connection_error
          | :timeout
          | :retry_failed
          | {:status_error, pos_integer()}
          | term()

  @impl Jido.Signal.Dispatch.Adapter
  @doc """
  Validates the HTTP adapter configuration options.

  ## Parameters

  * `opts` - Keyword list of options to validate

  ## Options

  * `:url` - Must be a valid URL string
  * `:method` - Must be one of #{inspect(@valid_methods)}
  * `:headers` - Must be a list of string tuples
  * `:timeout` - Must be a positive integer
  * `:retry` - Must be a valid retry configuration map

  ## Returns

  * `{:ok, validated_opts}` - Options are valid
  * `{:error, reason}` - Options are invalid with reason
  """
  @spec validate_opts(Keyword.t()) :: {:ok, Keyword.t()} | {:error, term()}
  def validate_opts(opts) do
    with {:ok, url} <- validate_url(Keyword.get(opts, :url)),
         {:ok, method} <- validate_method(Keyword.get(opts, :method, @default_method)),
         {:ok, headers} <- validate_headers(Keyword.get(opts, :headers, [])),
         {:ok, timeout} <- validate_timeout(Keyword.get(opts, :timeout, @default_timeout)),
         {:ok, retry} <- validate_retry(Keyword.get(opts, :retry, @default_retry)) do
      {:ok,
       opts
       |> Keyword.put(:url, url)
       |> Keyword.put(:method, method)
       |> Keyword.put(:headers, headers)
       |> Keyword.put(:timeout, timeout)
       |> Keyword.put(:retry, retry)}
    end
  end

  @impl Jido.Signal.Dispatch.Adapter
  @doc """
  Delivers a signal via HTTP request.

  ## Parameters

  * `signal` - The signal to deliver
  * `opts` - Validated options from `validate_opts/1`

  ## Returns

  * `:ok` - Signal was delivered successfully
  * `{:error, reason}` - Delivery failed with reason

  ## Examples

      iex> signal = %Jido.Signal{type: "user:created", data: %{id: 123}}
      iex> Http.deliver(signal, [url: "https://api.example.com/events"])
      :ok
  """
  @spec deliver(Jido.Signal.t(), delivery_opts()) :: :ok | {:error, delivery_error()}
  def deliver(signal, opts) do
    url = Keyword.fetch!(opts, :url)
    method = Keyword.fetch!(opts, :method)
    headers = Keyword.fetch!(opts, :headers)
    timeout = Keyword.fetch!(opts, :timeout)
    retry_config = Keyword.fetch!(opts, :retry)

    body = Jason.encode!(signal)
    default_headers = [{"content-type", "application/json"}]
    headers = default_headers ++ headers

    do_request_with_retry(method, url, headers, body, timeout, retry_config)
  end

  # Private Helpers

  defp validate_url(nil), do: {:error, "url is required"}

  defp validate_url(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{scheme: scheme, host: host}
      when not is_nil(scheme) and not is_nil(host) and scheme in ["http", "https"] ->
        {:ok, url}

      _ ->
        {:error, "invalid url: #{url} - must be an HTTP or HTTPS URL"}
    end
  end

  defp validate_url(invalid), do: {:error, "url must be a string, got: #{inspect(invalid)}"}

  defp validate_method(method) when method in @valid_methods, do: {:ok, method}
  defp validate_method(invalid), do: {:error, "invalid method: #{inspect(invalid)}"}

  defp validate_headers(headers) when is_list(headers) do
    if Enum.all?(headers, &valid_header?/1) do
      {:ok, headers}
    else
      {:error, "invalid headers format"}
    end
  end

  defp validate_headers(invalid), do: {:error, "headers must be a list, got: #{inspect(invalid)}"}

  defp valid_header?({key, value}) when is_binary(key) and is_binary(value), do: true
  defp valid_header?(_), do: false

  defp validate_timeout(timeout) when is_integer(timeout) and timeout > 0, do: {:ok, timeout}
  defp validate_timeout(_), do: {:error, "timeout must be a positive integer"}

  defp validate_retry(%{} = retry) do
    with {:ok, max_attempts} <- validate_positive_integer(retry.max_attempts, :max_attempts),
         {:ok, base_delay} <- validate_positive_integer(retry.base_delay, :base_delay),
         {:ok, max_delay} <- validate_positive_integer(retry.max_delay, :max_delay) do
      {:ok,
       %{
         max_attempts: max_attempts,
         base_delay: base_delay,
         max_delay: max_delay
       }}
    end
  end

  defp validate_retry(invalid), do: {:error, "invalid retry configuration: #{inspect(invalid)}"}

  defp validate_positive_integer(value, _field) when is_integer(value) and value > 0,
    do: {:ok, value}

  defp validate_positive_integer(invalid, field),
    do: {:error, "#{field} must be a positive integer, got: #{inspect(invalid)}"}

  defp do_request_with_retry(method, url, headers, body, timeout, retry_config, attempt \\ 1) do
    case do_request(method, url, headers, body, timeout) do
      :ok ->
        :ok

      {:error, reason} = error ->
        if should_retry?(attempt, retry_config) do
          delay = calculate_delay(attempt, retry_config)
          Logger.warning("HTTP request failed, retrying in #{delay}ms: #{inspect(reason)}")
          Process.sleep(delay)
          do_request_with_retry(method, url, headers, body, timeout, retry_config, attempt + 1)
        else
          Logger.error("HTTP request failed after #{attempt} attempts: #{inspect(reason)}")
          error
        end
    end
  end

  defp do_request(method, url, headers, body, timeout) do
    url_charlist = to_charlist(url)

    # Convert headers to charlists for :httpc
    headers_charlist = Enum.map(headers, fn {k, v} -> {to_charlist(k), to_charlist(v)} end)

    request = {url_charlist, headers_charlist, ~c"application/json", body}

    case :httpc.request(method, request, [{:timeout, timeout}], []) do
      {:ok, {{_, status_code, _}, _headers, _body}}
      when status_code >= 200 and status_code < 300 ->
        :ok

      {:ok, {{_, status_code, _}, _headers, body}} ->
        {:error, {:status_error, status_code, body}}

      {:error, {:failed_connect, [{:to_address, _}, {:inet, [:inet], reason}]}}
      when reason in [:timeout, :econnrefused] ->
        {:error, :timeout}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp should_retry?(attempt, %{max_attempts: max_attempts}), do: attempt < max_attempts

  defp calculate_delay(attempt, %{base_delay: base_delay, max_delay: max_delay}) do
    delay = trunc(base_delay * :math.pow(2, attempt - 1))
    min(delay, max_delay)
  end
end
