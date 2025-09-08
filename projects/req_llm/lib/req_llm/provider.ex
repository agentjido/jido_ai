defmodule ReqLLM.Provider do
  @moduledoc """
  Behavior for LLM provider implementations.

  Providers implement this behavior to handle model-specific request configuration,
  response parsing, and streaming. Each provider is a Req plugin that uses the
  standard Req request/response pipeline.

  ## Provider Responsibilities

  - **Request Configuration**: Set headers, base URLs, authentication
  - **Body Building**: Format messages and options for provider API
  - **Response Parsing**: Convert API responses to standardized format
  - **Streaming**: Handle Server-Sent Events and convert to StreamChunk stream
  - **Usage Extraction**: Parse usage/cost data from responses

  ## Implementation Pattern

  Providers use `ReqLLM.Provider.DSL` to define their configuration and then
  implement the callbacks defined in this behavior.

  ## Examples

      defmodule MyProvider do
        @behaviour ReqLLM.Provider

        use ReqLLM.Provider.DSL,
          id: :myprovider,
          base_url: "https://api.example.com/v1",
          metadata: "priv/models_dev/myprovider.json"

        @impl ReqLLM.Provider
        def attach(request, model, opts) do
          # Configure request for this provider
          request
          |> add_auth_headers()
          |> set_body_and_url()
        end

        @impl ReqLLM.Provider
        def parse_response(response, model) do
          # Parse non-streaming response
          {:ok, [%ReqLLM.StreamChunk{type: :text, text: "..."}]}
        end

        # ... other callbacks
      end

  """

  @doc """
  Attaches provider-specific configuration to a Req request.

  This callback is called by `ReqLLM.attach/2` to configure the request
  for the specific provider. It should set up authentication, base URLs,
  request bodies, and any provider-specific headers.

  ## Parameters

    * `request` - The Req.Request struct to configure
    * `model` - The ReqLLM.Model struct with model specification
    * `opts` - Additional options (messages, tools, etc.)

  ## Returns

    * `Req.Request.t()` - The configured request ready for execution

  """
  @callback attach(Req.Request.t(), ReqLLM.Model.t(), keyword()) :: Req.Request.t()

  @doc """
  Parses a non-streaming API response into StreamChunk format.

  This callback processes successful API responses and converts them
  into a standardized list of StreamChunk structs.

  ## Parameters

    * `response` - The Req.Response struct from the API
    * `model` - The ReqLLM.Model struct used for the request

  ## Returns

    * `{:ok, [ReqLLM.StreamChunk.t()]}` - Parsed response as chunks
    * `{:error, term()}` - Parse error

  """
  @callback parse_response(Req.Response.t(), ReqLLM.Model.t()) ::
              {:ok, [ReqLLM.StreamChunk.t()]} | {:error, term()}

  @doc """
  Parses a streaming API response into a StreamChunk stream.

  This callback processes Server-Sent Events responses and converts them
  into a lazy Stream of StreamChunk structs for back-pressure handling.

  ## Parameters

    * `response` - The Req.Response struct with streaming body
    * `model` - The ReqLLM.Model struct used for the request

  ## Returns

    * `{:ok, Stream.t()}` - Lazy stream of ReqLLM.StreamChunk structs
    * `{:error, term()}` - Parse error

  """
  @callback parse_stream(Req.Response.t(), ReqLLM.Model.t()) ::
              {:ok, Stream.t()} | {:error, term()}

  @doc """
  Extracts usage/cost metadata from API response.

  This callback parses usage information (token counts, costs) from
  the API response for telemetry and billing purposes.

  ## Parameters

    * `response` - The Req.Response struct from the API
    * `model` - The ReqLLM.Model struct used for the request

  ## Returns

    * `{:ok, map()}` - Usage metadata map
    * `{:error, term()}` - Extraction error

  """
  @callback extract_usage(Req.Response.t(), ReqLLM.Model.t()) ::
              {:ok, map()} | {:error, term()}

  @doc """
  Registry function to get provider module for a provider ID.

  ## Parameters

    * `provider_id` - Atom identifying the provider (e.g., :anthropic)

  ## Returns

    * `{:ok, module()}` - Provider module that implements this behavior
    * `{:error, term()}` - Provider not found

  """
  @spec get(atom()) :: {:ok, module()} | {:error, term()}
  def get(provider_id) do
    ReqLLM.Provider.Registry.get_provider(provider_id)
  end

  @doc """
  Registry function with bang syntax (raises on error).
  """
  @spec get!(atom()) :: module()
  def get!(provider_id) do
    case get(provider_id) do
      {:ok, module} -> module
      {:error, reason} -> raise ArgumentError, "Provider not found: #{inspect(reason)}"
    end
  end
end
