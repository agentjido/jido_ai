defmodule Jido.AI.ReAct.Token do
  @moduledoc """
  Signed checkpoint tokens for caller-owned ReAct continuation.
  """

  import Bitwise

  alias Jido.AI.ReAct.{Config, State}

  @prefix "rt1."
  @issuer "jido_ai/react"
  @version 1

  @type payload :: %{
          required(:v) => pos_integer(),
          required(:iss) => String.t(),
          required(:run_id) => String.t(),
          required(:request_id) => String.t(),
          required(:iat_ms) => integer(),
          required(:exp_ms) => integer() | nil,
          required(:config_fingerprint) => String.t(),
          required(:state) => map()
        }

  @spec issue(State.t(), Config.t()) :: String.t()
  def issue(%State{} = state, %Config{} = config) do
    now = now_ms()
    exp = if is_integer(config.token.ttl_ms), do: now + config.token.ttl_ms, else: nil

    payload = %{
      v: @version,
      iss: @issuer,
      run_id: state.run_id,
      request_id: state.request_id,
      iat_ms: now,
      exp_ms: exp,
      config_fingerprint: Config.fingerprint(config),
      state: State.minimal_checkpoint_map(state)
    }

    payload_bin = encode_payload(payload, config)
    signature = sign(payload_bin, config.token.secret)

    @prefix <> base64url(payload_bin) <> "." <> base64url(signature)
  end

  @spec decode(String.t(), Config.t()) :: {:ok, payload()} | {:error, term()}
  def decode(token, %Config{} = config) when is_binary(token) do
    with {:ok, payload_bin, sig_bin} <- split_and_decode(token),
         :ok <- verify_signature(payload_bin, sig_bin, config.token.secret),
         {:ok, payload} <- decode_payload(payload_bin),
         :ok <- validate_payload(payload, config) do
      {:ok, payload}
    end
  end

  @spec decode_state(String.t(), Config.t()) :: {:ok, State.t(), payload()} | {:error, term()}
  def decode_state(token, %Config{} = config) do
    with {:ok, payload} <- decode(token, config),
         {:ok, state} <- State.from_checkpoint_map(payload.state) do
      {:ok, state, payload}
    end
  end

  @spec mark_cancelled(String.t(), Config.t(), atom()) :: {:ok, String.t()} | {:error, term()}
  def mark_cancelled(token, %Config{} = config, reason) when is_atom(reason) do
    with {:ok, state, _payload} <- decode_state(token, config) do
      cancelled_state =
        state
        |> State.put_status(:cancelled)
        |> State.put_result("Request cancelled (reason: #{inspect(reason)})")

      {:ok, issue(cancelled_state, config)}
    end
  end

  defp split_and_decode(@prefix <> rest) do
    case String.split(rest, ".", parts: 2) do
      [payload_part, sig_part] ->
        with {:ok, payload_bin} <- base64url_decode(payload_part),
             {:ok, sig_bin} <- base64url_decode(sig_part) do
          {:ok, payload_bin, sig_bin}
        end

      _ ->
        {:error, :invalid_token_format}
    end
  end

  defp split_and_decode(_), do: {:error, :invalid_token_prefix}

  defp verify_signature(payload_bin, sig_bin, secret) do
    expected = sign(payload_bin, secret)

    if secure_compare(expected, sig_bin) do
      :ok
    else
      {:error, :invalid_token_signature}
    end
  rescue
    _ -> {:error, :invalid_token_signature}
  end

  defp decode_payload(payload_bin) do
    try do
      {:ok, :erlang.binary_to_term(payload_bin, [:safe])}
    rescue
      _ -> {:error, :invalid_token_payload}
    end
  end

  defp validate_payload(payload, %Config{} = config) when is_map(payload) do
    cond do
      payload[:v] != @version ->
        {:error, :token_version_mismatch}

      payload[:iss] != @issuer ->
        {:error, :invalid_token_issuer}

      expired?(payload[:exp_ms]) ->
        {:error, :token_expired}

      payload[:config_fingerprint] != Config.fingerprint(config) ->
        {:error, :token_config_mismatch}

      not is_map(payload[:state]) ->
        {:error, :invalid_token_state}

      true ->
        :ok
    end
  end

  defp validate_payload(_payload, _config), do: {:error, :invalid_token_payload}

  defp expired?(nil), do: false
  defp expired?(exp_ms) when is_integer(exp_ms), do: now_ms() > exp_ms
  defp expired?(_), do: true

  defp encode_payload(payload, %Config{} = config) do
    if config.token.compress? do
      :erlang.term_to_binary(payload, compressed: 6)
    else
      :erlang.term_to_binary(payload)
    end
  end

  defp sign(payload_bin, secret) when is_binary(secret) do
    :crypto.mac(:hmac, :sha256, secret, payload_bin)
  end

  defp secure_compare(left, right) when is_binary(left) and is_binary(right) do
    if byte_size(left) == byte_size(right) do
      do_secure_compare(left, right, 0) == 0
    else
      false
    end
  end

  defp secure_compare(_, _), do: false

  defp do_secure_compare(<<>>, <<>>, acc), do: acc

  defp do_secure_compare(<<l, rest_left::binary>>, <<r, rest_right::binary>>, acc) do
    do_secure_compare(rest_left, rest_right, acc ||| bxor(l, r))
  end

  defp base64url(binary), do: Base.url_encode64(binary, padding: false)

  defp base64url_decode(encoded) do
    case Base.url_decode64(encoded, padding: false) do
      {:ok, bin} -> {:ok, bin}
      :error -> {:error, :invalid_base64}
    end
  end

  defp now_ms, do: System.system_time(:millisecond)
end
