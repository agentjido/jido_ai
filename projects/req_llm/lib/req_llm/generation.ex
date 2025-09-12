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
                        default: "auto",
                        doc: "Tool choice strategy"
                      ],
                      system_prompt: [type: :string, doc: "System prompt to prepend"],
                      provider_options: [type: :map, doc: "Provider-specific options"],
                      reasoning: [
                        type: {:in, [nil, false, true, "low", "auto", "high"]},
                        doc: "Request reasoning tokens from the model"
                      ],
                      stream_format: [
                        type: {:in, [:sse, :chunked, :json]},
                        default: :sse,
                        doc: "Provider specific streaming transport format"
                      ],
                      chunk_timeout: [
                        type: :pos_integer,
                        default: 30_000,
                        doc: "How long to wait between chunks before aborting (ms)"
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
         # Merge model options with validated opts for request options
         request_options <- prepare_request_options(context, model, validated_opts),
         request =
           Req.new(
             method: :post,
             receive_timeout: 30_000
           ),
         configured_request <- provider_module.attach(request, model, request_options),
         {:ok, %Req.Response{body: tagged_response}} <- Req.request(configured_request),
         {:ok, response} <- Response.decode(tagged_response, model) do
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
         request_options <- prepare_request_options(context, model, stream_opts),
         request = Req.new(method: :post),
         configured_request <- provider_module.attach(request, model, request_options),
         {:ok, %Req.Response{body: tagged_response}} <- Req.request(configured_request),
         {:ok, response} <- Response.decode(tagged_response, model) do
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

  @doc """
  Extracts token usage information from a ReqLLM result.

  Designed to be used in a pipeline after `generate_text` or `stream_text` calls.
  Works with both Response objects (from `generate_text/3`) and plain results (from `generate_text!/3`).

  ## Parameters

    * `result` - The result tuple from any ReqLLM function

  ## Examples

      # Generate text with usage info - pipeline style
      {:ok, text, usage} = 
        ReqLLM.Generation.generate_text("openai:gpt-4o", "Hello")
        |> ReqLLM.Generation.with_usage()
      
      usage
      #=> %{tokens: %{input: 10, output: 15}, cost: 0.00075}

      # Works with bang functions too (returns nil usage)
      {:ok, text, usage} = 
        ReqLLM.Generation.generate_text!("openai:gpt-4o", "Hello")
        |> ReqLLM.Generation.with_usage()
      
      usage  #=> nil

      # Stream text with usage info
      {:ok, stream, usage} = 
        ReqLLM.Generation.stream_text("openai:gpt-4o", "Hello")
        |> ReqLLM.Generation.with_usage()

  """
  @spec with_usage({:ok, any()} | {:error, term()}) ::
          {:ok, String.t() | Enumerable.t(), map() | nil} | {:error, term()}
  def with_usage({:ok, %Response{} = response}) do
    # Extract usage from ReqLLM.Response
    usage = Response.usage(response)

    content =
      if response.stream?, do: Response.text_stream(response), else: Response.text(response)

    {:ok, content, usage}
  end

  def with_usage({:ok, result}) do
    # Graceful passthrough for results without response metadata (like from bang functions)
    {:ok, result, nil}
  end

  def with_usage({:error, error}) do
    {:error, error}
  end

  @doc """
  Extracts cost information from a ReqLLM result.

  Designed to be used in a pipeline after `generate_text` or `stream_text` calls.
  Works with both Response objects (from `generate_text/3`) and plain results (from `generate_text!/3`).

  ## Parameters

    * `result` - The result tuple from any ReqLLM function

  ## Examples

      # Generate text with cost info - pipeline style
      {:ok, text, cost} = 
        ReqLLM.Generation.generate_text("openai:gpt-4o", "Hello")
        |> ReqLLM.Generation.with_cost()
      
      cost
      #=> 0.00075

      # Works with bang functions too (returns nil cost)
      {:ok, text, cost} = 
        ReqLLM.Generation.generate_text!("openai:gpt-4o", "Hello")
        |> ReqLLM.Generation.with_cost()
      
      cost  #=> nil

      # Stream text with cost info - pipeline style
      {:ok, stream, cost} = 
        ReqLLM.Generation.stream_text("openai:gpt-4o", "Hello")
        |> ReqLLM.Generation.with_cost()

  """
  @spec with_cost({:ok, any()} | {:error, term()}) ::
          {:ok, String.t() | Enumerable.t(), float() | nil} | {:error, term()}
  def with_cost(result) do
    case with_usage(result) do
      {:ok, content, %{cost: cost}} -> {:ok, content, cost}
      {:ok, content, _} -> {:ok, content, nil}
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

  defp prepare_request_options(context, model, validated_opts) do
    # Build options that the provider attach/3 function expects
    model_options =
      [
        model: model.model,
        context: context,
        temperature: validated_opts[:temperature],
        max_tokens: validated_opts[:max_tokens],
        top_p: validated_opts[:top_p],
        presence_penalty: validated_opts[:presence_penalty],
        frequency_penalty: validated_opts[:frequency_penalty],
        tools: validated_opts[:tools],
        tool_choice: validated_opts[:tool_choice],
        stream: validated_opts[:stream?],
        system: validated_opts[:system_prompt]
      ]
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)

    # Add provider-specific options if present
    case validated_opts[:provider_options] do
      nil ->
        model_options

      provider_opts when is_map(provider_opts) ->
        Keyword.merge(model_options, Map.to_list(provider_opts))
    end
  end
end
