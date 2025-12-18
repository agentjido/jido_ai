defmodule Jido.Signal.Dispatch.Webhook do
  @moduledoc """
  An adapter for dispatching signals to webhooks.

  This adapter implements the `Jido.Signal.Dispatch.Adapter` behaviour and extends
  the HTTP adapter with webhook-specific functionality. It provides features like:

  * Signature generation for webhook payloads
  * Standard webhook headers
  * Webhook-specific retry policies
  * Event type mapping

  ## Configuration Options

  * `:url` - (required) The webhook URL to send the request to
  * `:secret` - (optional) Secret key for generating signatures
  * `:signature_header` - (optional) Header name for the signature, defaults to "x-webhook-signature"
  * `:event_type_header` - (optional) Header name for the event type, defaults to "x-webhook-event"
  * `:event_type_map` - (optional) Map of signal types to webhook event types
  * All other options from `Jido.Signal.Dispatch.Http`

  ## Examples

      # Basic webhook with signature
      config = {:webhook, [
        url: "https://api.example.com/webhook",
        secret: "webhook_secret"
      ]}

      # Advanced configuration
      config = {:webhook, [
        url: "https://api.example.com/webhook",
        secret: "webhook_secret",
        signature_header: "x-signature",
        event_type_header: "x-event-type",
        event_type_map: %{
          "user:created" => "user.created",
          "user:updated" => "user.updated"
        },
        timeout: 10_000,
        retry: %{
          max_attempts: 5,
          base_delay: 2000,
          max_delay: 10000
        }
      ]}

  ## Webhook Signatures

  When a secret is provided, the adapter will:
  1. Generate a signature of the payload using HMAC-SHA256
  2. Add the signature to the request headers
  3. Include a timestamp to prevent replay attacks

  ## Event Type Mapping

  The adapter can map internal signal types to external webhook event types:

      event_type_map = %{
        "user:created" => "user.created",
        "user:updated" => "user.updated"
      }

  If no mapping is provided, the original signal type is used.

  ## Error Handling

  In addition to HTTP adapter errors, this adapter handles:

  * `:invalid_secret` - Secret key is not valid
  * `:invalid_event_type_map` - Event type mapping is invalid
  """

  @behaviour Jido.Signal.Dispatch.Adapter
  require Logger

  @default_signature_header "x-webhook-signature"
  @default_event_type_header "x-webhook-event"
  @default_timestamp_header "x-webhook-timestamp"

  @type webhook_opts :: [
          url: String.t(),
          secret: String.t() | nil,
          signature_header: String.t(),
          event_type_header: String.t(),
          event_type_map: %{String.t() => String.t()} | nil
        ]
  @type webhook_error ::
          :invalid_secret | :invalid_event_type_map | Jido.Signal.Dispatch.Http.delivery_error()

  @impl Jido.Signal.Dispatch.Adapter
  @doc """
  Validates the webhook adapter configuration options.

  ## Parameters

  * `opts` - Keyword list of options to validate

  ## Options

  * `:url` - Must be a valid URL string
  * `:secret` - Must be a string or nil
  * `:signature_header` - Must be a string
  * `:event_type_header` - Must be a string
  * `:event_type_map` - Must be a map of strings to strings

  ## Returns

  * `{:ok, validated_opts}` - Options are valid
  * `{:error, reason}` - Options are invalid with reason
  """
  @spec validate_opts(Keyword.t()) :: {:ok, Keyword.t()} | {:error, term()}
  def validate_opts(opts) do
    with {:ok, _} <- Jido.Signal.Dispatch.Http.validate_opts(opts),
         {:ok, secret} <- validate_secret(Keyword.get(opts, :secret)),
         {:ok, signature_header} <-
           validate_header_name(
             Keyword.get(opts, :signature_header, @default_signature_header),
             :signature_header
           ),
         {:ok, event_type_header} <-
           validate_header_name(
             Keyword.get(opts, :event_type_header, @default_event_type_header),
             :event_type_header
           ),
         {:ok, event_type_map} <- validate_event_type_map(Keyword.get(opts, :event_type_map)) do
      {:ok,
       opts
       |> Keyword.put(:secret, secret)
       |> Keyword.put(:signature_header, signature_header)
       |> Keyword.put(:event_type_header, event_type_header)
       |> Keyword.put(:event_type_map, event_type_map)}
    end
  end

  @impl Jido.Signal.Dispatch.Adapter
  @doc """
  Delivers a signal via webhook.

  ## Parameters

  * `signal` - The signal to deliver
  * `opts` - Validated options from `validate_opts/1`

  ## Returns

  * `:ok` - Signal was delivered successfully
  * `{:error, reason}` - Delivery failed with reason

  ## Examples

      iex> signal = %Jido.Signal{type: "user:created", data: %{id: 123}}
      iex> Webhook.deliver(signal, [url: "https://api.example.com/webhook", secret: "secret"])
      :ok
  """
  @spec deliver(Jido.Signal.t(), webhook_opts()) :: :ok | {:error, webhook_error()}
  def deliver(signal, opts) do
    # Prepare the payload
    payload = Jason.encode!(signal)
    timestamp = DateTime.utc_now() |> DateTime.to_unix()

    # Generate webhook-specific headers
    webhook_headers =
      []
      |> add_signature_header(payload, timestamp, opts)
      |> add_event_type_header(signal, opts)
      |> add_timestamp_header(timestamp)

    # Merge with existing headers
    headers = (Keyword.get(opts, :headers, []) ++ webhook_headers) |> Enum.uniq_by(&elem(&1, 0))

    # Delegate to HTTP adapter
    opts = Keyword.put(opts, :headers, headers)
    Jido.Signal.Dispatch.Http.deliver(signal, opts)
  end

  # Private Helpers

  defp validate_secret(nil), do: {:ok, nil}
  defp validate_secret(secret) when is_binary(secret), do: {:ok, secret}
  defp validate_secret(_invalid), do: {:error, "secret must be a string or nil"}

  defp validate_header_name(name, _field) when is_binary(name), do: {:ok, name}
  defp validate_header_name(_invalid, field), do: {:error, "#{field} must be a string"}

  defp validate_event_type_map(nil), do: {:ok, nil}

  defp validate_event_type_map(map) when is_map(map) do
    if Enum.all?(map, fn {k, v} -> is_binary(k) and is_binary(v) end) do
      {:ok, map}
    else
      {:error, "event_type_map must contain only string keys and values"}
    end
  end

  defp validate_event_type_map(invalid),
    do: {:error, "event_type_map must be a map or nil, got: #{inspect(invalid)}"}

  defp add_signature_header(headers, payload, timestamp, opts) do
    case Keyword.get(opts, :secret) do
      nil ->
        headers

      secret ->
        signature = generate_signature(payload, timestamp, secret)
        [{Keyword.get(opts, :signature_header), signature} | headers]
    end
  end

  defp add_event_type_header(headers, signal, opts) do
    event_type = map_event_type(signal.type, Keyword.get(opts, :event_type_map))
    [{Keyword.get(opts, :event_type_header, @default_event_type_header), event_type} | headers]
  end

  defp add_timestamp_header(headers, timestamp) do
    [{@default_timestamp_header, to_string(timestamp)} | headers]
  end

  defp generate_signature(payload, timestamp, secret) do
    string_to_sign = "#{timestamp}.#{payload}"

    :crypto.mac(:hmac, :sha256, secret, string_to_sign)
    |> Base.encode16(case: :lower)
  end

  defp map_event_type(type, nil), do: type
  defp map_event_type(type, map), do: Map.get(map, type, type)
end
