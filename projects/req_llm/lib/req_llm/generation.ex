defmodule ReqLLM.Generation do
  @moduledoc """
  Text generation functionality for ReqLLM.

  This module provides the core text generation capabilities including:
  - Text generation with full response metadata
  - Text streaming with metadata
  - Usage and cost extraction utilities

  All functions follow Vercel AI SDK patterns and return structured responses
  with proper error handling.
  """

  alias ReqLLM.{Model, Context, Response}

  # Base text generation schema - shared by generate_text and stream_text
  @text_opts_schema NimbleOptions.new!(
                      temperature: [
                        type: :float,
                        doc: "Controls randomness in the output (0.0 to 2.0)"
                      ],
                      max_tokens: [
                        type: :pos_integer,
                        doc: "Maximum number of tokens to generate"
                      ],
                      top_p: [type: :float, doc: "Nucleus sampling parameter"],
                      presence_penalty: [
                        type: :float,
                        doc: "Penalize new tokens based on presence"
                      ],
                      frequency_penalty: [
                        type: :float,
                        doc: "Penalize new tokens based on frequency"
                      ],
                      tools: [type: :any, doc: "List of tool definitions"],
                      tool_choice: [
                        type: {:or, [:string, :atom, :map]},
                        doc: "Tool choice strategy"
                      ],
                      system_prompt: [type: :string, doc: "System prompt to prepend"],
                      provider_options: [type: :map, doc: "Provider-specific options"],
                      reasoning: [
                        type: {:in, [nil, false, true, "low", "auto", "high"]},
                        doc: "Request reasoning tokens from the model"
                      ]
                    )

  @doc """
  Generates text using an AI model with full response metadata.

  Returns a canonical ReqLLM.Response which includes usage data, context, and metadata.
  For simple text-only results, use `generate_text!/3`.

  ## Parameters

    * `model_spec` - Model specification in various formats
    * `messages` - Text prompt or list of messages
    * `opts` - Additional options (keyword list)

  ## Options

    * `:temperature` - Control randomness in responses (0.0 to 2.0)
    * `:max_tokens` - Limit the length of the response
    * `:top_p` - Nucleus sampling parameter
    * `:presence_penalty` - Penalize new tokens based on presence
    * `:frequency_penalty` - Penalize new tokens based on frequency
    * `:tools` - List of tool definitions
    * `:tool_choice` - Tool choice strategy
    * `:system_prompt` - System prompt to prepend
    * `:provider_options` - Provider-specific options

  ## Examples

      {:ok, response} = ReqLLM.Generation.generate_text("anthropic:claude-3-sonnet", "Hello world")
      ReqLLM.Response.text(response)
      #=> "Hello! How can I assist you today?"

      # Access usage metadata
      ReqLLM.Response.usage(response)
      #=> %{input_tokens: 10, output_tokens: 8}

  """
  @spec generate_text(
          String.t() | {atom(), keyword()} | struct(),
          String.t() | list(),
          keyword()
        ) :: {:ok, Response.t()} | {:error, term()}
  def generate_text(model_spec, messages, opts \\ []) do
    with {:ok, validated_opts} <- NimbleOptions.validate(opts, @text_opts_schema),
         {:ok, model} <- Model.from(model_spec),
         {:ok, provider_module} <- ReqLLM.provider(model.provider),
         context <- build_context(messages, validated_opts),
         {:ok, configured_request} <-
           provider_module.prepare_request(:chat, model, context, validated_opts),
         {:ok, %Req.Response{body: decoded_response}} <- Req.request(configured_request),
         {:ok, response} <- Response.decode_response(decoded_response, model) do
      {:ok, response}
    end
  end

  @doc """
  Generates text using an AI model, returning only the text content.

  This is a convenience function that extracts just the text from the response.
  For access to usage metadata and other response data, use `generate_text/3`.

  ## Parameters

  Same as `generate_text/3`.

  ## Examples

      {:ok, text} = ReqLLM.Generation.generate_text!("anthropic:claude-3-sonnet", "Hello world")
      text
      #=> "Hello! How can I assist you today?"

  """
  @spec generate_text!(
          String.t() | {atom(), keyword()} | struct(),
          String.t() | list(),
          keyword()
        ) :: {:ok, String.t()} | {:error, term()}
  def generate_text!(model_spec, messages, opts \\ []) do
    case generate_text(model_spec, messages, opts) do
      {:ok, response} -> {:ok, Response.text(response)}
      {:error, error} -> {:error, error}
    end
  end

  @doc """
  Streams text generation using an AI model with full response metadata.

  Returns a canonical ReqLLM.Response containing usage data and stream.
  For simple streaming without metadata, use `stream_text!/3`.

  ## Parameters

  Same as `generate_text/3`.

  ## Examples

      {:ok, response} = ReqLLM.Generation.stream_text("anthropic:claude-3-sonnet", "Tell me a story")
      ReqLLM.Response.text_stream(response) |> Enum.each(&IO.write/1)

      # Access usage metadata after streaming  
      ReqLLM.Response.usage(response)
      #=> %{input_tokens: 15, output_tokens: 42}

  """
  @spec stream_text(
          String.t() | {atom(), keyword()} | struct(),
          String.t() | list(),
          keyword()
        ) :: {:ok, Response.t()} | {:error, term()}
  def stream_text(model_spec, messages, opts \\ []) do
    with {:ok, validated_opts} <- NimbleOptions.validate(opts, @text_opts_schema),
         {:ok, model} <- Model.from(model_spec),
         {:ok, provider_module} <- ReqLLM.provider(model.provider),
         stream_opts = Keyword.put(validated_opts, :stream?, true),
         context <- build_context(messages, stream_opts),
         {:ok, configured_request} <-
           provider_module.prepare_request(:chat, model, context, stream_opts),
         {:ok, %Req.Response{body: decoded_response}} <- Req.request(configured_request),
         {:ok, response} <- Response.decode_response(decoded_response, model) do
      {:ok, response}
    end
  end

  @doc """
  Streams text generation using an AI model, returning only the stream.

  This is a convenience function that extracts just the stream from the response.
  For access to usage metadata and other response data, use `stream_text/3`.

  ## Parameters

  Same as `stream_text/3`.

  ## Examples

      {:ok, stream} = ReqLLM.Generation.stream_text!("anthropic:claude-3-sonnet", "Tell me a story")
      stream |> Enum.each(&IO.write/1)

  """
  @spec stream_text!(
          String.t() | {atom(), keyword()} | struct(),
          String.t() | list(),
          keyword()
        ) :: {:ok, Enumerable.t()} | {:error, term()}
  def stream_text!(model_spec, messages, opts \\ []) do
    case stream_text(model_spec, messages, opts) do
      {:ok, response} -> {:ok, Response.text_stream(response)}
      {:error, error} -> {:error, error}
    end
  end

  # Private helper functions

  defp build_context(messages, opts) when is_binary(messages) do
    context = Context.new([Context.user(messages)])
    add_system_prompt(context, opts)
  end

  defp build_context(%Context{} = context, opts) do
    add_system_prompt(context, opts)
  end

  defp build_context(messages, opts) when is_list(messages) do
    # Convert plain message maps to Context if needed
    message_structs =
      Enum.map(messages, fn
        %ReqLLM.Message{} = message ->
          message

        %{role: role, content: content} = message ->
          Context.text(
            String.to_existing_atom(to_string(role)),
            content,
            Map.get(message, :metadata, %{})
          )

        other ->
          other
      end)

    context = Context.new(message_structs)
    add_system_prompt(context, opts)
  end

  defp add_system_prompt(%Context{} = context, opts) do
    case opts[:system_prompt] do
      nil ->
        context

      system_text when is_binary(system_text) ->
        system_msg = Context.system(system_text)
        Context.new([system_msg | Context.to_list(context)])
    end
  end
end
