defmodule ReqLLM.Provider do
  @moduledoc """
  Behavior for LLM provider implementations.

  Providers implement this behavior to handle model-specific request configuration,
  body encoding, response parsing, and usage extraction. Each provider is a Req plugin
  that uses the standard Req request/response pipeline.

  ## Provider Responsibilities

  - **Request Configuration**: Set headers, base URLs, authentication via `attach/3`
  - **Body Encoding**: Transform Context to provider-specific JSON via `encode_body/1`
  - **Response Parsing**: Decode API responses via `decode_response/1`
  - **Usage Extraction**: Parse usage/cost data via `extract_usage/2` (optional)

  ## Implementation Pattern

  Providers use `ReqLLM.Provider.DSL` to define their configuration and implement
  the required callbacks as Req pipeline steps.

  ## Examples

      defmodule MyProvider do
        @behaviour ReqLLM.Provider

        use ReqLLM.Provider.DSL,
          id: :myprovider,
          base_url: "https://api.example.com/v1",
          metadata: "priv/models_dev/myprovider.json"

        @impl ReqLLM.Provider
        def attach(request, model, opts) do
          request
          |> add_auth_headers()
          |> Req.Request.append_request_steps(llm_encode_body: &encode_body/1)
          |> Req.Request.append_response_steps(llm_decode_response: &decode_response/1)
        end

        def encode_body(request) do
          # Transform request.options[:context] to provider JSON
        end

        def decode_response({req, resp}) do
          # Parse response body and return {req, updated_resp}
        end
      end

  """

  @doc """
  Attaches provider-specific configuration to a Req request.

  This callback configures the request for the specific provider by setting up
  authentication, base URLs, and registering request/response pipeline steps.

  ## Parameters

    * `request` - The Req.Request struct to configure
    * `model` - The ReqLLM.Model struct with model specification
    * `opts` - Additional options (messages, tools, streaming, etc.)

  ## Returns

    * `Req.Request.t()` - The configured request with pipeline steps attached

  """
  @callback attach(Req.Request.t(), ReqLLM.Model.t(), keyword()) :: Req.Request.t()

  @doc """
  Encodes request body for provider API.

  This callback is typically used as a Req request step that transforms the
  request options (especially `:context`) into the provider-specific JSON body.

  ## Parameters

    * `request` - The Req.Request struct with options to encode

  ## Returns

    * `Req.Request.t()` - Request with encoded body

  """
  @callback encode_body(Req.Request.t()) :: Req.Request.t()

  @doc """
  Decodes provider API response.

  This callback is typically used as a Req response step that transforms the
  raw API response into a standardized format for ReqLLM consumption.

  ## Parameters

    * `request_response` - Tuple of {Req.Request.t(), Req.Response.t()}

  ## Returns

    * `{Req.Request.t(), Req.Response.t() | Exception.t()}` - Decoded response or error

  """
  @callback decode_response({Req.Request.t(), Req.Response.t()}) ::
              {Req.Request.t(), Req.Response.t() | Exception.t()}

  @doc """
  Extracts usage/cost metadata from response body (optional).

  This callback is called by `ReqLLM.Step.Usage` if the provider module
  exports this function. It allows custom usage extraction beyond the
  standard formats.

  ## Parameters

    * `body` - The response body (typically a map)
    * `model` - The ReqLLM.Model struct (may be nil)

  ## Returns

    * `{:ok, map()}` - Usage metadata map with keys like `:input`, `:output`
    * `{:error, term()}` - Extraction error

  """
  @callback extract_usage(term(), ReqLLM.Model.t() | nil) ::
              {:ok, map()} | {:error, term()}

  @doc """
  Returns the default environment variable name for API authentication.

  This callback provides the fallback environment variable name when the
  provider metadata doesn't specify one. Generated automatically by the
  DSL if `default_env_key` is provided.

  ## Returns

    * `String.t()` - Environment variable name (e.g., "ANTHROPIC_API_KEY")

  """
  @callback default_env_key() :: String.t()

  @optional_callbacks [extract_usage: 2, default_env_key: 0]

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
      {:error, _reason} -> raise ReqLLM.Error.Invalid.Provider.exception(provider: provider_id)
    end
  end
end
