defprotocol ReqLLM.Response.Codec do
  @moduledoc """
  Protocol for decoding provider response data to canonical ReqLLM.Response.

  Handles both tagged wrapper structs and direct raw data decoding, eliminating
  wrap_response friction for simpler APIs.

  ## Zero-Ceremony Direct Decoding

  The protocol now supports direct decoding without requiring provider-specific
  wrapper structs, using model information to dispatch to the correct provider:

      # Direct decoding from raw response data
      ReqLLM.Response.Codec.decode(raw_anthropic_json, model)
      #=> {:ok, %ReqLLM.Response{}}

      # Still supports tagged wrapper approach for internal use
      wrapped_response |> ReqLLM.Response.Codec.decode()
      #=> {:ok, %ReqLLM.Response{}}

  ## Implementation

  Each provider implements this protocol for their specific tagged wrapper struct
  AND raw data types by implementing decode/1 and decode/2:

      defimpl ReqLLM.Response.Codec, for: MyProvider.Response do
        def decode(%MyProvider.Response{data: raw_data, model: model}) do
          decode_raw_data(raw_data, model)
        end

        def decode(raw_data, model) when is_map(raw_data) do
          decode_raw_data(raw_data, model)
        end

        def encode(_), do: {:error, :not_implemented}
      end

  """

  @fallback_to_any true

  @doc """
  Decode provider response to canonical ReqLLM.Response.

  Accepts either tagged wrapper structs or raw response data with model.

  ## Parameters

    * `data_or_tagged` - Raw response data OR provider-tagged wrapper struct

  ## Returns

    * `{:ok, %ReqLLM.Response{}}` on successful decoding
    * `{:error, reason}` if decoding fails

  ## Examples

      # Tagged wrapper decoding (internal use)
      raw_data
      |> ReqLLM.Providers.Anthropic.Response.new(model)
      |> ReqLLM.Response.Codec.decode_response()

  """
  @spec decode_response(t()) :: {:ok, ReqLLM.Response.t()} | {:error, term()}
  def decode_response(data_or_tagged)

  @doc """
  Decode raw provider response data directly with model information.

  This eliminates the need for wrap_response friction by allowing direct
  decoding from raw response data using model information for provider dispatch.

  ## Parameters

    * `raw_data` - Raw provider response data (map, stream, etc.)
    * `model` - Model struct containing provider information

  ## Returns

    * `{:ok, %ReqLLM.Response{}}` on successful decoding
    * `{:error, reason}` if decoding fails

  ## Examples

      # Direct decoding (zero-ceremony API)
      ReqLLM.Response.Codec.decode_response(raw_anthropic_json, model)
      #=> {:ok, %ReqLLM.Response{context: ctx, message: msg, ...}}

  """
  @spec decode_response(t(), ReqLLM.Model.t()) :: {:ok, ReqLLM.Response.t()} | {:error, term()}
  def decode_response(raw_data, model)

  @doc """
  Encode canonical response back to provider format (optional).

  ## Parameters

    * `tagged_response` - A provider-specific tagged struct containing ReqLLM.Response

  ## Returns

    * Provider-specific response format
    * `{:error, :not_implemented}` if encoding is not supported

  """
  @spec encode_request(t()) :: term() | {:error, term()}
  def encode_request(tagged_response)
end

defimpl ReqLLM.Response.Codec, for: Any do
  @doc """
  Default implementation for unsupported types.

  Returns an error indicating that no codec implementation exists for the given type.
  This ensures graceful failure when attempting to use an unsupported provider
  or when a provider hasn't implemented the response codec protocol.
  """
  def decode_response(_), do: {:error, :not_implemented}
  def decode_response(_, _), do: {:error, :not_implemented}
  def encode_request(_), do: {:error, :not_implemented}
end
