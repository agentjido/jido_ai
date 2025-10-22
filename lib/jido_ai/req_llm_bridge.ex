defmodule Jido.AI.ReqLlmBridge do
  @moduledoc """
  Bridge module for integrating ReqLLM with Jido AI.

  This module provides the translation layer between Jido AI's current interfaces
  and ReqLLM's API, ensuring seamless interoperability while preserving backward
  compatibility.

  Key responsibilities:
  - Message format conversion between Jido AI and ReqLLM
  - Error mapping to preserve existing error structures
  - Response shape transformation to maintain API contracts
  - Logging integration preservation
  """

  require Logger

  alias Jido.AI.ReqLlmBridge.{Authentication, StreamingAdapter, ToolBuilder}

  @doc """
  Converts Jido AI message format to ReqLLM context format.

  ReqLLM supports both string prompts and message structures. This function
  converts Jido AI's message format to the appropriate ReqLLM format.

  ## Parameters
    - messages: List of Jido AI message maps with :role and :content

  ## Returns
    - ReqLLM context or string prompt

  ## Examples

      iex> messages = [%{role: :user, content: "Hello"}]
      iex> Jido.AI.ReqLlmBridge.convert_messages(messages)
      [%{role: :user, content: "Hello"}]
  """
  @spec convert_messages(list(map())) :: list(map()) | String.t()
  def convert_messages([%{role: :user, content: content}]) do
    # For simple single user messages, use string format
    content
  end

  def convert_messages(messages) when is_list(messages) do
    # For complex conversations, use message format
    Enum.map(messages, &convert_message/1)
  end

  @doc """
  Converts a single Jido AI message to ReqLLM message format.

  ## Parameters
    - message: Map with :role and :content keys

  ## Returns
    - Map in ReqLLM message format
  """
  @spec convert_message(map()) :: map()
  def convert_message(%{role: role, content: content}) do
    %{role: role, content: content}
  end

  @doc """
  Converts ReqLLM response to Jido AI response format.

  Preserves the existing response structure that Jido AI consumers expect.

  ## Parameters
    - response: ReqLLM response (map or struct)

  ## Returns
    - Map in Jido AI response format
  """
  @spec convert_response(map() | struct()) :: map()
  def convert_response(response) when is_map(response) do
    %{
      content: get_response_text(response),
      usage: convert_usage(response[:usage] || response["usage"]),
      tool_calls: convert_tool_calls(response[:tool_calls] || response["tool_calls"] || []),
      finish_reason: response[:finish_reason] || response["finish_reason"]
    }
  end

  @doc """
  Maps ReqLLM errors to Jido AI error format.

  Preserves existing `{:ok, result} | {:error, reason}` patterns and error structures.

  ## Parameters
    - error: ReqLLM error term

  ## Returns
    - Jido AI compatible error term
  """
  @spec map_error(term()) :: {:error, term()}
  def map_error({:error, %{status: status, body: body}}) do
    {:error,
     %{
       reason: "http_error",
       details: "HTTP #{status}: #{inspect(body)}",
       status: status,
       body: body
     }}
  end

  def map_error({:error, %{__struct__: struct_name} = error}) when is_atom(struct_name) do
    # Handle ReqLLM struct errors
    {:error,
     %{
       reason: Map.get(error, :reason, "req_llm_error"),
       details: Map.get(error, :message, inspect(error)),
       original_error: error
     }}
  end

  def map_error({:error, error}) when is_map(error) do
    {:error,
     %{
       reason: error[:type] || error["type"] || "req_llm_error",
       details: error[:message] || error["message"] || inspect(error),
       original_error: error
     }}
  end

  def map_error({:error, %Req.TransportError{} = error}) do
    {:error,
     %{
       reason: "transport_error",
       details: Exception.message(error),
       original_error: error
     }}
  end

  def map_error({:error, reason}) when is_binary(reason) do
    {:error,
     %{
       reason: "req_llm_error",
       details: reason
     }}
  end

  def map_error({:error, reason}) do
    {:error,
     %{
       reason: "unknown_error",
       details: inspect(reason),
       original_error: reason
     }}
  end

  def map_error(other) do
    {:error,
     %{
       reason: "unexpected_error",
       details: "Unexpected error format: #{inspect(other)}",
       original_error: other
     }}
  end

  @doc """
  Builds ReqLLM request options from Jido AI parameters.

  Maps Jido AI parameters to ReqLLM's expected option format, including
  enhanced tool choice parameter handling for the new tool system.

  ## Parameters
    - params: Map of Jido AI parameters

  ## Returns
    - Map of ReqLLM options

  ## Examples

      iex> params = %{temperature: 0.7, tool_choice: "auto", max_tokens: 150}
      iex> Jido.AI.ReqLlmBridge.build_req_llm_options(params)
      %{temperature: 0.7, tool_choice: "auto", max_tokens: 150}
  """
  @spec build_req_llm_options(map()) :: map()
  def build_req_llm_options(params) do
    params
    |> Map.take([:temperature, :max_tokens, :top_p, :stop, :tools, :tool_choice])
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
    |> maybe_process_tool_choice()
  end

  @doc """
  Maps Jido tool choice preferences to ReqLLM tool choice format.

  Converts Jido-style tool choice specifications to the format expected
  by ReqLLM, supporting various tool selection modes and constraints.

  ## Parameters
    - tool_choice: Tool choice specification (atom, string, or map)

  ## Returns
    - ReqLLM-compatible tool choice parameter

  ## Examples

      iex> Jido.AI.ReqLlmBridge.map_tool_choice_parameters(:auto)
      "auto"

      iex> Jido.AI.ReqLlmBridge.map_tool_choice_parameters({:function, "specific_tool"})
      %{type: "function", function: %{name: "specific_tool"}}
  """
  @spec map_tool_choice_parameters(atom() | String.t() | map()) :: String.t() | map()
  def map_tool_choice_parameters(tool_choice)

  # Standard choices
  def map_tool_choice_parameters(:auto), do: "auto"
  def map_tool_choice_parameters("auto"), do: "auto"
  def map_tool_choice_parameters(:none), do: "none"
  def map_tool_choice_parameters("none"), do: "none"
  def map_tool_choice_parameters(:required), do: "required"
  def map_tool_choice_parameters("required"), do: "required"

  # Specific function selection
  def map_tool_choice_parameters({:function, function_name}) when is_binary(function_name) do
    %{
      type: "function",
      function: %{name: function_name}
    }
  end

  def map_tool_choice_parameters({:function, function_name}) when is_atom(function_name) do
    map_tool_choice_parameters({:function, to_string(function_name)})
  end

  # Multiple function selection (provider-specific)
  def map_tool_choice_parameters({:functions, function_list}) when is_list(function_list) do
    # Some providers support limiting to a set of functions
    # For now, fall back to "auto" - this could be enhanced per provider
    Logger.debug("Multiple function selection not directly supported, using auto",
      functions: function_list
    )

    "auto"
  end

  # Map format (pass through if already in correct format)
  def map_tool_choice_parameters(%{type: _type} = tool_choice), do: tool_choice

  # Fallback for unknown formats
  def map_tool_choice_parameters(tool_choice) do
    Logger.warning("Unknown tool choice format, defaulting to auto",
      tool_choice: tool_choice
    )

    "auto"
  end

  @doc """
  Converts Jido AI tools to ReqLLM tool format.

  This function maintains backward compatibility while using the enhanced ToolBuilder
  system for improved tool conversion. It provides a facade over the new architecture
  while preserving the existing API contract.

  ## Parameters
    - tools: List of Jido Action modules

  ## Returns
    - {:ok, list(ReqLlmBridge.Tool.t())} on success
    - {:error, reason} on failure

  ## Examples

      iex> tools = [Jido.Actions.Basic.Sleep, Jido.Actions.Basic.Log]
      iex> {:ok, descriptors} = Jido.AI.ReqLlmBridge.convert_tools(tools)
      iex> length(descriptors)
      2
  """
  @spec convert_tools(list(module())) :: {:ok, list(ReqLlmBridge.Tool.t())} | {:error, term()}
  def convert_tools(tools) when is_list(tools) do
    # Use the new ToolBuilder system for enhanced conversion
    case ToolBuilder.batch_convert(tools) do
      {:ok, tool_descriptors} ->
        # Convert tool descriptors to ReqLLM tool format
        reqllm_tools = Enum.map(tool_descriptors, &tool_descriptor_to_reqllm_tool/1)
        {:ok, reqllm_tools}

      {:error, reason} ->
        # Map errors to maintain backward compatibility
        {:error,
         %{
           reason: "tool_conversion_error",
           details: "Failed to convert tools using ToolBuilder",
           original_error: reason
         }}
    end
  rescue
    error ->
      {:error,
       %{
         reason: "tool_conversion_error",
         details: Exception.message(error),
         original_error: error
       }}
  end

  @doc """
  Converts Jido Action tools to ReqLLM tool format with enhanced options.

  Provides access to the enhanced tool conversion system while maintaining
  backward compatibility. Allows for additional conversion options and
  context passing.

  ## Parameters
    - tools: List of Jido Action modules
    - opts: Conversion options (context, timeout, validation settings)

  ## Returns
    - {:ok, list(ReqLlmBridge.Tool.t())} on success
    - {:error, reason} on failure

  ## Examples

      iex> opts = %{context: %{user_id: 123}, validate_schema: true}
      iex> {:ok, descriptors} = Jido.AI.ReqLlmBridge.convert_tools_with_options(tools, opts)
  """
  @spec convert_tools_with_options(list(module()), map()) ::
          {:ok, list(ReqLlmBridge.Tool.t())} | {:error, term()}
  def convert_tools_with_options(tools, opts \\ %{}) when is_list(tools) and is_map(opts) do
    case ToolBuilder.batch_convert(tools, opts) do
      {:ok, tool_descriptors} ->
        reqllm_tools = Enum.map(tool_descriptors, &tool_descriptor_to_reqllm_tool/1)
        {:ok, reqllm_tools}

      {:error, reason} ->
        {:error,
         %{
           reason: "enhanced_tool_conversion_error",
           details: "Failed to convert tools with enhanced options",
           original_error: reason
         }}
    end
  end

  @doc """
  Validates that a Jido Action is compatible with ReqLLM tool conversion.

  Provides a way to check Action compatibility before attempting conversion,
  which can help catch issues early in the development process.

  ## Parameters
    - action_module: The Jido Action module to validate

  ## Returns
    - :ok if the Action is compatible
    - {:error, reason} if compatibility issues are found

  ## Examples

      iex> Jido.AI.ReqLlmBridge.validate_tool_compatibility(Jido.Actions.Basic.Sleep)
      :ok

      iex> Jido.AI.ReqLlmBridge.validate_tool_compatibility(InvalidAction)
      {:error, %{reason: "invalid_action_module"}}
  """
  @spec validate_tool_compatibility(module()) :: :ok | {:error, map()}
  def validate_tool_compatibility(action_module) when is_atom(action_module) do
    ToolBuilder.validate_action_compatibility(action_module)
  end

  @doc """
  Converts ReqLLM streaming response to Jido AI streaming format.

  Transforms a ReqLLM streaming response into the expected chunk format
  for Jido AI consumers, maintaining backward compatibility.

  ## Parameters
    - stream: ReqLLM streaming response (enumerable of chunks)
    - opts: Conversion options (optional)
      - :enhanced - Use enhanced streaming adapter (default: false)
      - Other options passed to StreamingAdapter if enhanced mode enabled

  ## Returns
    - Transformed stream with Jido AI compatible chunk format
  """
  @spec convert_streaming_response(Enumerable.t(), keyword()) :: Enumerable.t()
  def convert_streaming_response(stream, opts \\ []) do
    if Keyword.get(opts, :enhanced, false) do
      # Use enhanced streaming adapter for advanced functionality
      StreamingAdapter.adapt_stream(stream, opts)
    else
      # Use basic transformation for backward compatibility
      Stream.map(stream, &transform_streaming_chunk/1)
    end
  end

  @doc """
  Transforms a single ReqLLM streaming chunk to Jido AI format.

  Converts individual streaming chunks from ReqLLM format to the format
  expected by Jido AI consumers.

  ## Parameters
    - chunk: ReqLLM streaming chunk (map or struct)

  ## Returns
    - Map in Jido AI streaming chunk format
  """
  @spec transform_streaming_chunk(map() | struct()) :: map()
  def transform_streaming_chunk(chunk) when is_map(chunk) do
    %{
      content: get_chunk_content(chunk),
      finish_reason: chunk[:finish_reason] || chunk["finish_reason"],
      usage: convert_usage(chunk[:usage] || chunk["usage"]),
      tool_calls: convert_tool_calls(chunk[:tool_calls] || chunk["tool_calls"] || []),
      delta: %{
        content: get_chunk_content(chunk),
        role: chunk[:role] || chunk["role"] || "assistant"
      }
    }
  end

  @doc """
  Maps ReqLLM streaming errors to Jido AI error format.

  Handles streaming-specific errors and maps them to the error format
  expected by Jido AI consumers.

  ## Parameters
    - error: ReqLLM streaming error term

  ## Returns
    - Jido AI compatible error term
  """
  @spec map_streaming_error(term()) :: {:error, term()}
  def map_streaming_error({:error, %{reason: "stream_error"} = error}) do
    {:error,
     %{
       reason: "streaming_error",
       details: "Streaming failed: #{error.message || inspect(error)}",
       original_error: error
     }}
  end

  def map_streaming_error({:error, %{reason: "timeout"} = error}) do
    {:error,
     %{
       reason: "streaming_timeout",
       details: "Stream timed out: #{error.message || inspect(error)}",
       original_error: error
     }}
  end

  def map_streaming_error(error) do
    # Fall back to regular error mapping for non-streaming errors
    map_error(error)
  end

  @doc """
  Logs ReqLLM operations preserving Jido AI's opt-in logging behavior.

  Only logs when explicitly enabled, maintaining the current minimal logging approach.

  ## Parameters
    - level: Log level (:debug, :info, :warning, :error)
    - message: Log message
    - metadata: Additional metadata (optional)
  """
  @spec log_operation(atom(), String.t(), keyword()) :: :ok
  def log_operation(level, message, metadata \\ []) do
    # Only log if explicitly enabled via configuration
    if Application.get_env(:jido_ai, :enable_req_llm_logging, false) do
      Logger.log(
        level,
        "[ReqLLM Bridge] #{message}",
        Keyword.merge([module: __MODULE__], metadata)
      )
    end

    :ok
  end

  # Private helper functions

  defp tool_descriptor_to_reqllm_tool(tool_descriptor) when is_map(tool_descriptor) do
    # Convert ToolBuilder descriptor format to ReqLLM.tool/1 call result
    ReqLLM.tool(
      name: tool_descriptor.name,
      description: tool_descriptor.description,
      parameter_schema: tool_descriptor.parameter_schema,
      callback: tool_descriptor.callback
    )
  end

  defp maybe_process_tool_choice(options) when is_map(options) do
    case Map.get(options, :tool_choice) do
      nil ->
        options

      tool_choice ->
        processed_choice = map_tool_choice_parameters(tool_choice)
        Map.put(options, :tool_choice, processed_choice)
    end
  end

  defp get_response_text(response) do
    response[:text] || response["text"] ||
      response[:content] || response["content"] ||
      response[:message] || response["message"] ||
      ""
  end

  defp get_chunk_content(chunk) do
    # Extract content from streaming chunk
    chunk[:content] || chunk["content"] ||
      chunk[:text] || chunk["text"] ||
      chunk[:delta][:content] || chunk["delta"]["content"] ||
      ""
  end

  defp convert_usage(nil), do: nil

  defp convert_usage(usage) when is_map(usage) do
    # Map ReqLLM usage format to Jido AI expected format
    %{
      prompt_tokens: usage[:prompt_tokens] || usage["prompt_tokens"],
      completion_tokens: usage[:completion_tokens] || usage["completion_tokens"],
      total_tokens: usage[:total_tokens] || usage["total_tokens"]
    }
  end

  defp convert_tool_calls(nil), do: []
  defp convert_tool_calls([]), do: []

  defp convert_tool_calls(tool_calls) when is_list(tool_calls) do
    Enum.map(tool_calls, &convert_tool_call/1)
  end

  defp convert_tool_call(tool_call) when is_map(tool_call) do
    %{
      id: tool_call[:id] || tool_call["id"],
      type: tool_call[:type] || tool_call["type"] || "function",
      function: %{
        name: tool_call[:function][:name] || tool_call["function"]["name"],
        arguments: tool_call[:function][:arguments] || tool_call["function"]["arguments"]
      }
    }
  end

  # Key Management Integration Functions

  @doc """
  Gets API key for ReqLLM provider with integrated Jido session support.

  This function bridges ReqLLM's key requirements with Jido's hierarchical
  key management, including process-specific session values.

  ## Parameters

    * `provider` - ReqLLM provider atom (e.g., :openai, :anthropic)
    * `req_options` - Request options that may contain :api_key override
    * `default` - Default value if key not found

  ## Returns

    * API key string if found, otherwise default value

  ## Examples

      # Standard provider key lookup
      key = get_provider_key(:openai)

      # With per-request override
      options = %{api_key: "sk-override"}
      key = get_provider_key(:openai, options)
  """
  @spec get_provider_key(atom(), map(), term()) :: String.t() | term()
  def get_provider_key(provider, req_options \\ %{}, default \\ nil) do
    case Authentication.authenticate_for_provider(provider, req_options) do
      {:ok, _headers, key} -> key
      {:error, _reason} -> default
    end
  end

  @doc """
  Gets authentication headers for a provider using the new authentication flow.

  Returns provider-specific authentication headers formatted according to each
  provider's requirements (Bearer tokens, API keys, version headers, etc.).

  ## Parameters

    * `provider` - The provider atom (e.g., :openai, :anthropic)
    * `req_options` - Request options that may contain api_key overrides

  ## Returns

    * Map of authentication headers ready for HTTP requests

  ## Examples

      # OpenAI Bearer token
      headers = get_provider_headers(:openai)
      # => %{"authorization" => "Bearer sk-..."}

      # Anthropic with version header
      headers = get_provider_headers(:anthropic)
      # => %{"x-api-key" => "sk-ant-...", "anthropic-version" => "2023-06-01"}

      # With per-request override
      options = %{api_key: "override-key"}
      headers = get_provider_headers(:openai, options)
  """
  @spec get_provider_headers(atom(), map()) :: map()
  def get_provider_headers(provider, req_options \\ %{}) do
    Authentication.get_authentication_headers(provider, req_options)
  end

  @doc """
  Gets both authentication key and headers for a provider.

  This function provides a unified interface for getting both the resolved
  API key and the formatted headers in a single call.

  ## Parameters

    * `provider` - The provider atom (e.g., :openai, :anthropic)
    * `req_options` - Request options that may contain api_key overrides

  ## Returns

    * `{:ok, {key, headers}}` - Both key and headers if authentication successful
    * `{:error, reason}` - Authentication error

  ## Examples

      {:ok, {key, headers}} = get_provider_authentication(:openai)
      # key => "sk-..."
      # headers => %{"authorization" => "Bearer sk-..."}

      {:ok, {key, headers}} = get_provider_authentication(:anthropic)
      # key => "sk-ant-..."
      # headers => %{"x-api-key" => "sk-ant-...", "anthropic-version" => "2023-06-01"}
  """
  @spec get_provider_authentication(atom(), map()) ::
          {:ok, {String.t(), map()}} | {:error, String.t()}
  def get_provider_authentication(provider, req_options \\ %{}) do
    case Authentication.authenticate_for_provider(provider, req_options) do
      {:ok, headers, key} -> {:ok, {key, headers}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Builds ReqLLM request options with integrated key management.

  Extends the existing build_req_llm_options/1 function with automatic
  key resolution using the integrated keyring system.

  ## Parameters

    * `params` - Map of Jido AI parameters
    * `provider` - ReqLLM provider atom for key resolution

  ## Returns

    * Map of ReqLLM options with resolved API key

  ## Examples

      params = %{temperature: 0.7, max_tokens: 150}
      options = build_req_llm_options_with_keys(params, :openai)
  """
  @spec build_req_llm_options_with_keys(map(), atom()) :: map()
  def build_req_llm_options_with_keys(params, provider) do
    # Build base options using existing function
    base_options = build_req_llm_options(params)

    # Add API key resolution if not already present
    case Map.get(base_options, :api_key) do
      nil ->
        # Resolve key using integrated keyring
        api_key = get_provider_key(provider, params)
        if api_key, do: Map.put(base_options, :api_key, api_key), else: base_options

      _existing_key ->
        # Keep existing key (per-request override)
        base_options
    end
  end

  @doc """
  Validates that required API keys are available for a provider.

  Checks key availability across all integrated systems (Jido session,
  environment, ReqLLM, JidoKeys) and reports the source.

  ## Parameters

    * `provider` - ReqLLM provider atom

  ## Returns

    * `{:ok, source}` if key is available
    * `{:error, :missing_key}` if no key found

  ## Examples

      case validate_provider_key(:openai) do
        {:ok, :session} -> # Key found in session
        {:error, :missing_key} -> # No key available
      end
  """
  @spec validate_provider_key(atom()) :: {:ok, atom()} | {:error, :missing_key}
  def validate_provider_key(provider) do
    case Authentication.validate_authentication(provider, %{}) do
      :ok -> {:ok, :available}
      {:error, _reason} -> {:error, :missing_key}
    end
  end

  @doc """
  Lists all available provider keys with their sources.

  Returns information about which providers have keys available
  and where those keys are sourced from.

  ## Returns

    * List of maps with provider and source information

  ## Examples

      providers = list_available_providers()
      # [%{provider: :openai, source: :environment}, ...]
  """
  @spec list_available_providers() :: [%{provider: atom(), source: atom()}]
  def list_available_providers do
    # Get providers from ReqLLM registry
    providers = get_reqllm_providers()

    providers
    |> Enum.map(fn provider ->
      case validate_provider_key(provider) do
        {:ok, source} -> %{provider: provider, source: source}
        {:error, :missing_key} -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp get_reqllm_providers do
    case Code.ensure_loaded(ReqLLM.Provider.Generated.ValidProviders) do
      {:module, module} ->
        module.list()

      _ ->
        # Fallback to legacy providers if ReqLLM not available
        [:openai, :anthropic, :openrouter, :google, :cloudflare]
    end
  rescue
    _ ->
      # Fallback to legacy providers on error
      [:openai, :anthropic, :openrouter, :google, :cloudflare]
  end
end
