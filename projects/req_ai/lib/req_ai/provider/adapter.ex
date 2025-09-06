defmodule ReqAI.Provider.Adapter do
  @moduledoc """
  Unified behaviour for AI provider adapter implementations.

  This behaviour defines the minimal contract that all AI provider adapters must implement:
  - `spec/0` - Returns provider metadata and configuration
  - `build_request/3` - Constructs the HTTP request for the provider
  - `parse_response/3` - Parses the provider's response into a standard format

  HTTP transport is handled separately by `ReqAI.HTTP.send/2`.

  ## Example Implementation

      defmodule MyProvider do
        @behaviour ReqAI.Provider.Adapter

        @impl true
        def spec do
          ReqAI.Provider.Spec.new(
            id: :my_provider,
            base_url: "https://api.example.com",
            auth: {:header, "authorization", :bearer},
            default_builder: __MODULE__,
            default_parser: __MODULE__
          )
        end

        @impl true
        def build_request(input, provider_opts, request_opts) do
          # Build HTTP request
        end

        @impl true
        def parse_response(response, provider_opts, request_opts) do
          # Parse HTTP response
        end
      end

  """

  @type provider_opts :: keyword()
  @type request_opts :: keyword()
  @type req_request :: Req.Request.t()
  @type req_response :: Req.Response.t()
  @type parsed_response :: String.t()

  @doc """
  Returns provider specification struct.

  ## Returns

  A `ReqAI.Provider.Spec` struct containing:
  - `:id` - Provider identifier atom
  - `:base_url` - Base URL for API requests
  - `:auth` - Authentication configuration tuple
  - `:default_builder` - Default builder module
  - `:default_parser` - Default parser module

  ## Example

      def spec do
        ReqAI.Provider.Spec.new(
          id: :openai,
          base_url: "https://api.openai.com",
          auth: {:header, "authorization", :bearer},
          default_builder: __MODULE__,
          default_parser: __MODULE__
        )
      end

  """
  @callback spec() :: ReqAI.Provider.Spec.t()

  @doc """
  Builds an HTTP request for the provider.

  ## Parameters

  - `input` - Input data (prompt, messages, etc.)
  - `provider_opts` - Provider-specific options
  - `request_opts` - Request-level options (model, temperature, etc.)

  ## Returns

  `{:ok, request}` where request is a Req.Request.t() struct, or
  `{:error, reason}` on failure.
  """
  @callback build_request(input :: term(), provider_opts, request_opts) ::
              {:ok, req_request} | {:error, term()}

  @doc """
  Parses an HTTP response from the provider.

  ## Parameters

  - `response` - HTTP response struct
  - `provider_opts` - Provider-specific options  
  - `request_opts` - Original request options

  ## Returns

  `{:ok, content}` where content is the parsed result, or
  `{:error, reason}` on failure.
  """
  @callback parse_response(response :: req_response, provider_opts, request_opts) ::
              {:ok, parsed_response} | {:error, term()}
end
