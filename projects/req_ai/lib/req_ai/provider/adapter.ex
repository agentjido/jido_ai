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
  - `parse_tool_call/2` - Extracts tool call arguments from provider responses
  - `stream_tool_init/1` - Initialize streaming tool call state (optional)
  - `stream_tool_accumulate/3` - Process streaming tool chunks (optional)

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

        @impl true
        def parse_tool_call(response_body, tool_name) do
          # Extract tool call arguments from provider response
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

  @doc """
  Extracts tool call arguments from provider response for a specific tool.

  ## Parameters

  - `response_body` - The raw response body map from the provider
  - `tool_name` - The name of the tool to extract arguments for

  ## Returns

  `{:ok, arguments}` where arguments can be a map, list, or string containing
  the tool call arguments, or `{:error, reason}` if the tool call is not found
  or cannot be parsed.

  ## Provider-specific Implementation Notes

  Different providers structure tool calls differently:

  - **OpenAI**: Extract from `response_body["choices"][0]["message"]["tool_calls"]`
    finding the tool by name in the array
  - **Anthropic**: Extract from `response_body["content"]` array finding
    tool_use blocks matching the tool name

  ## Example

      def parse_tool_call(response_body, tool_name) do
        case get_in(response_body, ["choices", Access.at(0), "message", "tool_calls"]) do
          tool_calls when is_list(tool_calls) ->
            case Enum.find(tool_calls, &(&1["function"]["name"] == tool_name)) do
              %{"function" => %{"arguments" => args}} -> {:ok, args}
              nil -> {:error, :tool_not_found}
            end
          _ ->
            {:error, :no_tool_calls}
        end
      end

  """
  @callback parse_tool_call(response_body :: map(), tool_name :: String.t()) ::
              {:ok, map() | list() | String.t()} | {:error, term()}

  @doc """
  Initializes provider-specific state for accumulating streaming tool call data.

  This callback is optional and provides default implementation returning `%{}`.
  Providers that support streaming tool calls should override this to set up
  any initial state needed for chunk accumulation.

  ## Parameters

  - `tool_name` - The name of the tool being called

  ## Returns

  Initial state for accumulating streaming chunks. Can be any term but typically
  a map containing parsing state, buffers, or counters.

  ## Provider-specific Examples

  **OpenAI**: Initialize with argument buffer and index tracking:

      def stream_tool_init(tool_name) do
        %{
          tool_name: tool_name,
          function_call: %{name: nil, arguments: ""},
          index: nil
        }
      end

  **Anthropic**: Initialize with content buffer and block tracking:

      def stream_tool_init(tool_name) do
        %{
          tool_name: tool_name,
          input: %{},
          partial_json: ""
        }
      end

  """
  @callback stream_tool_init(tool_name :: String.t()) :: any()

  @doc """
  Processes streaming chunks and returns completed argument objects.

  This callback is optional and provides default implementation returning
  `{state, []}` (no streaming support). Providers that support streaming tool
  calls should override this to accumulate chunks and detect completion.

  ## Parameters

  - `raw_chunk` - Raw chunk data from the stream (typically iodata/string)
  - `tool_name` - The name of the tool being called
  - `state` - Current accumulation state from `stream_tool_init/1` or previous calls

  ## Returns

  - `{new_state, completed}` - Updated state and list of completed argument maps
  - `{:error, reason}` - Error during chunk processing

  ## Provider-specific Examples

  **OpenAI**: Accumulate function call arguments from delta chunks:

      def stream_tool_accumulate(chunk, tool_name, state) do
        case Jason.decode(chunk) do
          {:ok, %{"choices" => [%{"delta" => %{"function_call" => fc}}]}} ->
            new_args = state.function_call.arguments <> (fc["arguments"] || "")
            new_state = put_in(state, [:function_call, :arguments], new_args)
            
            # Check if arguments are complete JSON
            case Jason.decode(new_args) do
              {:ok, parsed} -> {state, [parsed]}
              {:error, _} -> {new_state, []}
            end
          _ ->
            {state, []}
        end
      end

  **Anthropic**: Accumulate tool input from content delta chunks:

      def stream_tool_accumulate(chunk, tool_name, state) do
        case Jason.decode(chunk) do
          {:ok, %{"type" => "content_block_delta", "delta" => %{"partial_json" => json}}} ->
            new_json = state.partial_json <> json
            new_state = %{state | partial_json: new_json}
            
            case Jason.decode(new_json) do
              {:ok, parsed} -> {state, [parsed]}
              {:error, _} -> {new_state, []}
            end
          _ ->
            {state, []}
        end
      end

  """
  @callback stream_tool_accumulate(
              raw_chunk :: iodata(),
              tool_name :: String.t(),
              state :: any()
            ) :: {new_state :: any(), completed :: [map()]} | {:error, term()}

  @optional_callbacks stream_tool_init: 1, stream_tool_accumulate: 3

  defmacro __using__(_opts) do
    quote do
      @behaviour ReqAI.Provider.Adapter

      @impl ReqAI.Provider.Adapter
      def stream_tool_init(_tool_name), do: %{}

      @impl ReqAI.Provider.Adapter
      def stream_tool_accumulate(_raw_chunk, _tool_name, state), do: {state, []}

      defoverridable stream_tool_init: 1, stream_tool_accumulate: 3
    end
  end
end
