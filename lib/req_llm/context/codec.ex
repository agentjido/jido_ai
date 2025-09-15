defprotocol ReqLLM.Context.Codec do
  @moduledoc """
  Protocol for encoding canonical ReqLLM structures to provider wire JSON and decoding provider responses back to canonical structures.

  This protocol enables clean separation between data translation and transport concerns,
  allowing each provider to implement its own format conversion logic while maintaining
  a unified interface.

  ## Usage

      # Encoding: Canonical structures → Provider JSON
      context |> ReqLLM.Context.wrap(model) |> ReqLLM.Context.Codec.encode()

      # Decoding: Provider JSON → StreamChunks
      response_data |> provider_tagged_struct() |> ReqLLM.Context.Codec.decode()

  ## Implementation

  Each provider implements this protocol for their specific tagged wrapper struct:

      defimpl ReqLLM.Context.Codec, for: MyProvider.Tagged do
        def encode(%MyProvider.Tagged{context: ctx}) do
          # Convert ReqLLM.Context to provider JSON format
        end

        def decode(%MyProvider.Tagged{context: data}) do
          # Convert provider response to StreamChunks
        end
      end
  """

  @fallback_to_any true

  @doc """
  Encode canonical ReqLLM structures to provider wire JSON format for requests.

  Takes a provider-specific tagged wrapper struct containing a `ReqLLM.Context`
  and converts it to the JSON format expected by that provider's API.

  ## Parameters

    * `tagged_context` - A provider-specific tagged struct wrapping a `ReqLLM.Context`

  ## Returns

    * Provider-specific JSON structure ready for API transmission
    * `{:error, reason}` if encoding fails

  ## Examples

      # Anthropic encoding
      context
      |> ReqLLM.Providers.Anthropic.Tagged.new()
      |> ReqLLM.Context.Codec.encode_request()
      #=> %{system: "...", messages: [...], max_tokens: 4096}

  """
  @spec encode_request(t) :: term()
  def encode_request(tagged_context)

  @doc """
  Decode provider wire JSON back to canonical structures from responses.

  Takes a provider-specific tagged wrapper struct containing response data
  and converts it to a list of `ReqLLM.StreamChunk` structs or other canonical formats.

  ## Parameters

    * `tagged_data` - A provider-specific tagged struct wrapping response JSON

  ## Returns

    * List of `ReqLLM.StreamChunk.t()` structs
    * `{:error, reason}` if decoding fails

  ## Examples

      # Anthropic decoding
      response_data
      |> ReqLLM.Providers.Anthropic.Tagged.new()
      |> ReqLLM.Context.Codec.decode_response()
      #=> [%ReqLLM.StreamChunk{type: :text, text: "Hello!"}]

  """
  @spec decode_response(t) :: term()
  def decode_response(tagged_data)
end

defimpl ReqLLM.Context.Codec, for: Any do
  @doc """
  Default implementation for unsupported provider combinations.

  Returns an error indicating that no codec implementation exists for the given type.
  This ensures graceful failure when attempting to use an unsupported provider
  or when a provider hasn't implemented the codec protocol.
  """
  def encode_request(_), do: {:error, :not_implemented}
  def decode_response(_), do: {:error, :not_implemented}
end
