defmodule ReqAI.Provider.Adapter do
  @moduledoc """
  Unified behaviour for AI provider adapter implementations.

  This behaviour defines the complete contract that all AI provider adapters must implement:
  - `spec/0` - Returns provider metadata and configuration
  - `build_request/3` - Constructs the HTTP request for the provider
  - `parse_response/3` - Parses the provider's response into a standard format
  - `provider_info/0` - Returns basic provider information struct
  - `generate_text/3` - High-level text generation interface
  - `stream_text/3` - High-level text streaming interface

  HTTP transport is handled separately by `ReqAI.HTTP.send/2`.

  ## Example Implementation

      defmodule MyProvider do
        @behaviour ReqAI.Provider.Adapter

        @impl true
        def spec do
          ReqAI.Provider.Spec.new(
            id: :my_provider,
            base_url: "https://api.example.com",
            auth: {:header, "authorization", :bearer}
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
        
        @impl true
        def provider_info do
          ReqAI.Provider.new(:my_provider, "My Provider", "https://api.example.com")
        end

        @impl true
        def generate_text(model, messages, opts) do
          # High-level text generation implementation
        end

        @impl true
        def stream_text(model, messages, opts) do
          # High-level text streaming implementation
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

  @doc """
  Returns provider information struct.

  ## Returns

  A `ReqAI.Provider` struct containing basic provider metadata.

  ## Example

      def provider_info do
        ReqAI.Provider.new(:openai, "OpenAI", "https://api.openai.com")
      end

  """
  @callback provider_info() :: ReqAI.Provider.t()

  @doc """
  Generates text using the AI provider.

  ## Parameters

  - `model` - The model struct to use for generation
  - `messages` - The message(s) to process (string or list of messages)
  - `opts` - Options for generation (temperature, max_tokens, etc.)

  ## Returns

  `{:ok, text}` where text is the generated response, or
  `{:error, reason}` on failure.

  ## Example

      def generate_text(model, messages, opts) do
        with {:ok, request} <- build_request(messages, [], opts),
             {:ok, response} <- ReqAI.HTTP.send(request, opts),
             {:ok, text} <- parse_response(response, [], opts) do
          {:ok, text}
        end
      end

  """
  @callback generate_text(ReqAI.Model.t(), String.t() | [ReqAI.Message.t()], keyword()) ::
              {:ok, String.t()} | {:error, ReqAI.Error.t()}

  @doc """
  Streams text generation using the AI provider.

  ## Parameters

  - `model` - The model struct to use for generation
  - `messages` - The message(s) to process (string or list of messages)
  - `opts` - Options for generation (temperature, max_tokens, etc.)

  ## Returns

  `{:ok, stream}` where stream is an Enumerable of text chunks, or
  `{:error, reason}` on failure.

  ## Example

      def stream_text(model, messages, opts) do
        stream_opts = Keyword.put(opts, :stream?, true)
        with {:ok, request} <- build_request(messages, [], stream_opts),
             {:ok, response} <- ReqAI.HTTP.send(request, stream_opts) do
          {:ok, response}
        end
      end

  """
  @callback stream_text(ReqAI.Model.t(), String.t() | [ReqAI.Message.t()], keyword()) ::
              {:ok, Enumerable.t()} | {:error, ReqAI.Error.t()}
end
