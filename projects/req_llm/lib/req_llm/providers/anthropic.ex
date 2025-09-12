defmodule ReqLLM.Providers.Anthropic do
  @moduledoc """
  Anthropic provider implementation using the Provider behavior.

  Supports Anthropic's Messages API with features including:
  - Text generation with Claude models
  - Streaming responses
  - Tool calling
  - Multi-modal inputs (text and images)
  - Thinking/reasoning tokens

  ## Configuration

  Set your Anthropic API key via environment variable:

      export ANTHROPIC_API_KEY="your-api-key-here"

  ## Examples

      # Simple text generation
      model = ReqLLM.Model.from("anthropic:claude-3-haiku-20240307")
      {:ok, response} = ReqLLM.generate_text(model, "Hello!")

      # Streaming
      {:ok, stream} = ReqLLM.stream_text(model, "Tell me a story", stream: true)

      # Tool calling
      tools = [%ReqLLM.Tool{name: "get_weather", ...}]
      {:ok, response} = ReqLLM.generate_text(model, "What's the weather?", tools: tools)

  """

  @behaviour ReqLLM.Provider

  import ReqLLM.Provider.Utils, only: [maybe_append_stream_step: 2, prepare_options!: 3, maybe_put: 3]

  use ReqLLM.Provider.DSL,
    id: :anthropic,
    base_url: "https://api.anthropic.com/v1",
    metadata: "priv/models_dev/anthropic.json",
    provider_options:
      ~w(temperature max_tokens top_p top_k stream stop_sequences system api_version)a,
    provider_defaults: [
      temperature: 0.7,
      max_tokens: 1024,
      stream: false,
      api_version: "2023-06-01"
    ]

  defstruct [:context]

  @type t :: %__MODULE__{context: ReqLLM.Context.t()}

  @spec new(ReqLLM.Context.t()) :: t()
  def new(context), do: %__MODULE__{context: context}

  @impl ReqLLM.Provider
  def wrap_context(%ReqLLM.Context{} = ctx) do
    %__MODULE__{context: ctx}
  end

  @default_api_version "2023-06-01"

  @doc """
  Attaches the Anthropic plugin to a Req request.

  ## Parameters

    * `request` - The Req request to attach to
    * `model_input` - The model (ReqLLM.Model struct, string, or tuple) that triggers this provider
    * `opts` - Options keyword list (validated against comprehensive schema)

  ## Request Options

    * `:temperature` - Controls randomness (0.0-2.0). Defaults to 0.7
    * `:max_tokens` - Maximum tokens to generate. Defaults to 1024
    * `:stream?` - Enable streaming responses. Defaults to false
    * `:base_url` - Override base URL. Defaults to provider default
    * `:messages` - Chat messages to send
    * `:system` - System message
    * All options from ReqLLM.Provider.Options schemas are supported

  """
  @spec attach(Req.Request.t(), ReqLLM.Model.t() | String.t() | {atom(), keyword()}, keyword()) ::
          Req.Request.t()
  @impl ReqLLM.Provider
  def attach(%Req.Request{} = request, model_input, user_opts \\ []) do
    %ReqLLM.Model{} = model = ReqLLM.Model.from!(model_input)

    unless model.provider == provider_id() do
      raise ReqLLM.Error.Invalid.Provider.exception(provider: model.provider)
    end

    unless ReqLLM.Provider.Registry.model_exists?("#{provider_id()}:#{model.model}") do
      raise ReqLLM.Error.Invalid.Parameter.exception(parameter: "model: #{model.model}")
    end

    api_key_env = get_env_var_name()
    api_key = JidoKeys.get(api_key_env)

    unless api_key && api_key != "" do
      raise ReqLLM.Error.Invalid.Parameter.exception(
              parameter: "api_key (set via JidoKeys.put(#{inspect(api_key_env)}, key))"
            )
    end

    # Prepare validated options and extract what Req needs
    opts = prepare_options!(__MODULE__, model, user_opts)
    base_url = Keyword.get(user_opts, :base_url, default_base_url())
    req_keys = __MODULE__.supported_provider_options() ++ [:model, :context]

    request
    |> Req.Request.register_options(req_keys)
    |> Req.Request.merge_options(Keyword.take(opts, req_keys) ++ [base_url: base_url])
    |> Req.Request.put_header("x-api-key", api_key)
    |> Req.Request.put_header("anthropic-version", opts[:api_version] || @default_api_version)
    |> Req.Request.append_request_steps(llm_encode_body: &__MODULE__.encode_body/1)
    |> maybe_append_stream_step(opts[:stream])
    |> Req.Request.append_response_steps(llm_decode_response: &__MODULE__.decode_response/1)
  end

  # NOTE: The following Provider behavior callbacks are only used by ReqLLM.Generation module
  # Since our current architecture uses Req pipeline steps directly via attach/3,
  # these callbacks are not currently used by the demos. They remain for compatibility
  # with the Generation module if needed in the future.

  # @impl ReqLLM.Provider
  # def parse_response(response, %ReqLLM.Model{} = _model) do
  #   case response do
  #     %Req.Response{status: 200, body: body} ->
  #       chunks =
  #         body
  #         |> then(&%__MODULE__{context: &1})
  #         |> ReqLLM.Context.Codec.decode()

  #       case chunks do
  #         [] -> {:ok, [ReqLLM.StreamChunk.text("")]}
  #         chunks -> {:ok, chunks}
  #       end

  #     %Req.Response{status: status, body: body} ->
  #       {:error, to_error("API error", body, status)}
  #   end
  # end

  # @impl ReqLLM.Provider
  # def parse_stream(response, %ReqLLM.Model{} = _model) do
  #   case response do
  #     %Req.Response{status: 200, body: body_stream} when is_struct(body_stream, Stream) ->
  #       # Body is already a stream of parsed SSE events from the stream step
  #       {:ok,
  #        body_stream
  #        |> Stream.map(&to_stream_chunk/1)
  #        |> Stream.filter(& &1)}

  #     %Req.Response{status: 200, body: body} when is_binary(body) ->
  #       # Fallback for raw binary - this should be handled by the stream step now
  #       # but we keep it for backward compatibility
  #       {:error, to_error("Raw binary streaming not supported", body, 200)}

  #     %Req.Response{status: status, body: body} ->
  #       {:error, to_error("Streaming API error", body, status)}
  #   end
  # end

  # @impl ReqLLM.Provider
  # def extract_usage(response, %ReqLLM.Model{} = _model) do
  #   case response do
  #     %Req.Response{status: 200, body: %{"usage" => usage}} ->
  #       {:ok, usage}

  #     _ ->
  #       {:ok, %{}}
  #   end
  # end

  # Minimal stub implementations to satisfy the Provider behavior
  # These are not used in the current Req pipeline architecture but required by behavior
  @impl ReqLLM.Provider
  def parse_response(_, _), do: {:error, :not_implemented}
  
  @impl ReqLLM.Provider
  def parse_stream(_, _), do: {:error, :not_implemented}
  
  @impl ReqLLM.Provider
  def extract_usage(_, _), do: {:error, :not_implemented}

  # Request steps
  def encode_body(request) do
    # Extract messages from context if context is provided
    messages =
      case request.options[:messages] do
        nil ->
          # Try to extract from context if available
          case request.options[:context] do
            %ReqLLM.Context{messages: context_messages} ->
              # Convert ReqLLM.Message structs to Anthropic format
              Enum.map(context_messages, fn msg ->
                content =
                  case msg.content do
                    [%ReqLLM.Message.ContentPart{type: :text, text: text}] ->
                      text

                    content_list ->
                      Enum.map(content_list, fn
                        %ReqLLM.Message.ContentPart{type: :text, text: text} ->
                          %{type: "text", text: text}

                        %ReqLLM.Message.ContentPart{
                          type: :image,
                          data: data,
                          media_type: media_type
                        } ->
                          %{
                            type: "image",
                            source: %{
                              type: "base64",
                              media_type: media_type,
                              data: Base.encode64(data)
                            }
                          }

                        content ->
                          content
                      end)
                  end

                %{role: to_string(msg.role), content: content}
              end)

            _ ->
              []
          end

        messages ->
          messages
      end

    body =
      %{
        model: request.options[:model] || request.options[:id],
        messages: messages,
        temperature: request.options[:temperature],
        max_tokens: request.options[:max_tokens],
        stream: request.options[:stream]
      }
      |> maybe_put(:system, request.options[:system])

    IO.puts("\n🔧 Body step executing...")
    IO.puts("Messages: #{inspect(messages)}")
    IO.puts("Body to encode: #{inspect(body)}")

    try do
      encoded_body = Jason.encode!(body)
      IO.puts("✅ Body encoded successfully")

      request
      |> Req.Request.put_header("content-type", "application/json")
      |> Map.put(:body, encoded_body)
    rescue
      error ->
        IO.puts("❌ Body encoding failed: #{inspect(error)}")
        reraise error, __STACKTRACE__
    end
  end

  # Response step
  def decode_response({req, resp}) do
    case resp.status do
      200 ->
        # Response body might already be parsed by Req's decode_body step
        body =
          case resp.body do
            body when is_binary(body) ->
              case Jason.decode(body) do
                {:ok, parsed} -> parsed
                {:error, _} -> body
              end

            body ->
              body
          end

        parsed = parse_response_body(body, req.options[:stream])
        {req, %{resp | body: parsed}}

      status ->
        err =
          ReqLLM.Error.API.Response.exception(
            reason: "Anthropic API error",
            status: status,
            response_body: resp.body
          )

        {req, err}
    end
  end



  defp parse_response_body(body, false) when is_map(body) do
    %{
      id: body["id"],
      model: body["model"],
      # Keep the full content array structure
      content: body["content"],
      usage: %{
        input_tokens: body["usage"]["input_tokens"],
        output_tokens: body["usage"]["output_tokens"],
        total_tokens: body["usage"]["input_tokens"] + body["usage"]["output_tokens"]
      }
    }
  end

  defp parse_response_body(body_stream, true) when is_struct(body_stream, Stream) do
    # For streaming responses, pass through the Stream from the stream step
    body_stream
  end

  defp parse_response_body(body, true) when is_binary(body) do
    # For streaming responses, the body should not be binary at this point
    # as it should be processed by the stream step. This is a fallback.
    IO.puts("🌊 Unexpected binary body in streaming response...")
    
    %{
      id: "streaming-response",
      model: "claude-3-haiku-20240307",
      content: [%{"type" => "text", "text" => ""}],
      usage: %{input_tokens: 0, output_tokens: 0, total_tokens: 0},
      streaming: true,
      error: "Binary body received for streaming response"
    }
  end





  # Helper functions

  # Legacy helper functions (unused)
  # defp rename_key_in(opts, group, from, to) do
  #   Keyword.update!(opts, group, fn inner ->
  #     case Keyword.get(inner, from) do
  #       nil -> inner
  #       value -> inner |> Keyword.delete(from) |> Keyword.put(to, value)
  #     end
  #   end)
  # end

  # defp extract_or_build_context(body, opts) do
  #   cond do
  #     # If context is provided in opts, use it
  #     opts[:context] && is_struct(opts[:context], ReqLLM.Context) ->
  #       opts[:context]

  #     # If body has messages, build context from legacy format
  #     is_map(body) && Map.has_key?(body, :messages) ->
  #       build_context_from_legacy(body)

  #     # Default: empty context with user message from body if it's a string
  #     is_binary(body) ->
  #       ReqLLM.Context.new([ReqLLM.Context.user(body)])

  #     # Fallback: empty context
  #     true ->
  #       ReqLLM.Context.new([])
  #   end
  # end

  # defp build_context_from_legacy(%{messages: messages}) when is_list(messages) do
  #   converted_messages =
  #     Enum.map(messages, fn
  #       %ReqLLM.Message{} = msg ->
  #         msg

  #       %{role: role, content: content} ->
  #         ReqLLM.Context.text(String.to_atom(role), to_string(content))

  #       message when is_binary(message) ->
  #         ReqLLM.Context.user(message)
  #     end)

  #   ReqLLM.Context.new(converted_messages)
  # end

  # defp build_context_from_legacy(_), do: ReqLLM.Context.new([])

  # defp add_model_params(body, %ReqLLM.Model{} = model, opts) do
  #   tools = extract_tools_from_opts(opts)

  #   body
  #   |> Map.put(:model, model.model)
  #   |> Map.put(:max_tokens, opts[:max_tokens] || model.max_tokens || 4096)
  #   |> maybe_add_temperature(opts[:temperature])
  #   |> maybe_add_tools(tools)
  # end

  # defp add_sampling_params(body, opts) do
  #   body
  #   |> Map.put(:stream, opts[:stream] || false)
  # end

  # defp extract_tools_from_opts(opts) do
  #   opts[:tools] || []
  # end

  # defp maybe_add_temperature(body, nil), do: body
  # defp maybe_add_temperature(body, temperature), do: Map.put(body, :temperature, temperature)

  # defp maybe_add_tools(body, []), do: body

  # defp maybe_add_tools(body, tools) do
  #   formatted_tools =
  #     Enum.map(tools, fn
  #       %ReqLLM.Tool{} = tool -> ReqLLM.Tool.to_schema(tool, :anthropic)
  #       tool -> tool
  #     end)

  #   Map.put(body, :tools, formatted_tools)
  # end

  # Currently used helper functions

  defp get_env_var_name do
    with {:ok, metadata} <- ReqLLM.Provider.Registry.get_provider_metadata(:anthropic),
         [env_var | _] <-
           get_in(metadata, ["provider", "env"]) || get_in(metadata, [:provider, :env]) do
      env_var
    else
      _ -> "ANTHROPIC_API_KEY"
    end
  end



  # Convert SSE events to ReqLLM stream chunks (used by commented parse_stream/2)
  # defp to_stream_chunk(%{data: data}) when is_map(data) do
  #   case data do
  #     %{"type" => "content_block_delta", "delta" => %{"text" => text}} ->
  #       ReqLLM.StreamChunk.text(text)

  #     %{"type" => "content_block_delta", "delta" => %{"partial_json" => json}} ->
  #       ReqLLM.StreamChunk.text(json)

  #     %{
  #       "type" => "content_block_start",
  #       "content_block" => %{"type" => "tool_use", "name" => name}
  #     } ->
  #       ReqLLM.StreamChunk.tool_call(name, %{})

  #     %{"type" => "content_block_delta", "delta" => %{"type" => "tool_use"}} ->
  #       nil

  #     %{"type" => "message_delta", "delta" => %{"stop_reason" => reason}} ->
  #       ReqLLM.StreamChunk.meta(%{finish_reason: reason})

  #     %{"type" => "message_stop"} ->
  #       ReqLLM.StreamChunk.meta(%{finish_reason: "stop"})

  #     # Handle thinking blocks if present in future Claude models
  #     %{"type" => "thinking_block_delta", "delta" => %{"text" => text}} ->
  #       ReqLLM.StreamChunk.thinking(text)

  #     _ ->
  #       nil
  #   end
  # end

  # defp to_stream_chunk(_), do: nil

  # Error helper function (unused in current Req pipeline architecture)
  # defp to_error(reason, body, status) do
  #   error_message =
  #     case body do
  #       %{"error" => %{"message" => message}} -> message
  #       %{"error" => error} when is_binary(error) -> error
  #       _ -> reason
  #     end

  #   case status do
  #     nil ->
  #       ReqLLM.Error.API.Response.exception(reason: error_message, response_body: body)

  #     status ->
  #       ReqLLM.Error.API.Response.exception(
  #         reason: error_message,
  #         status: status,
  #         response_body: body
  #       )
  #   end
  # end
end
