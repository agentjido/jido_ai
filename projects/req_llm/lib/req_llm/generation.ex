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

  alias ReqLLM.Model

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
                      ]
                    )

  @doc """
  Generates text using an AI model with full response metadata.

  Returns the complete Req.Response which includes usage data, headers, and metadata.
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
      response.body
      #=> "Hello! How can I assist you today?"

      # Access usage metadata
      {:ok, text, usage} = ReqLLM.Generation.generate_text("anthropic:claude-3-sonnet", "Hello") |> ReqLLM.Generation.with_usage()

  """
  @spec generate_text(
          String.t() | {atom(), keyword()} | struct(),
          String.t() | list(),
          keyword()
        ) :: {:ok, Req.Response.t()} | {:error, term()}
  def generate_text(model_spec, messages, opts \\ []) do
    with {:ok, validated_opts} <- NimbleOptions.validate(opts, @text_opts_schema),
         {:ok, model} <- Model.from(model_spec),
         {:ok, provider_module} <- ReqLLM.provider(model.provider) do
      # Always return full response for metadata access
      enhanced_opts = Keyword.put(validated_opts, :return_response, true)
      provider_module.generate_text(model, messages, enhanced_opts)
    else
      {:error, :not_found} ->
        {:error, ReqLLM.Error.Invalid.Provider.exception(provider: "unknown")}

      error ->
        error
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
      {:ok, %Req.Response{body: body}} -> {:ok, body}
      {:error, error} -> {:error, error}
    end
  end

  @doc """
  Streams text generation using an AI model with full response metadata.

  Returns the complete response containing usage data and metadata.
  For simple streaming without metadata, use `stream_text!/3`.

  ## Parameters

  Same as `generate_text/3`.

  ## Examples

      {:ok, response} = ReqLLM.Generation.stream_text("anthropic:claude-3-sonnet", "Tell me a story")
      response.body |> Enum.each(&IO.write/1)

      # Access usage metadata after streaming
      {:ok, stream, usage} = ReqLLM.Generation.stream_text("anthropic:claude-3-sonnet", "Hello") |> ReqLLM.Generation.with_usage()

  """
  @spec stream_text(
          String.t() | {atom(), keyword()} | struct(),
          String.t() | list(),
          keyword()
        ) :: {:ok, Req.Response.t()} | {:error, term()}
  def stream_text(model_spec, messages, opts \\ []) do
    with {:ok, validated_opts} <- NimbleOptions.validate(opts, @text_opts_schema),
         {:ok, model} <- Model.from(model_spec),
         {:ok, provider_module} <- ReqLLM.provider(model.provider) do
      # Always return full response for metadata access
      enhanced_opts =
        validated_opts
        |> Keyword.put(:stream?, true)
        |> Keyword.put(:return_response, true)

      provider_module.stream_text(model, messages, enhanced_opts)
    else
      {:error, :not_found} ->
        {:error, ReqLLM.Error.Invalid.Provider.exception(provider: "unknown")}

      error ->
        error
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
      {:ok, %Req.Response{body: body}} -> {:ok, body}
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
  def with_usage({:ok, %Req.Response{body: body} = response}) do
    # Extract usage from response private data
    usage = get_in(response.private, [:req_llm, :usage])
    {:ok, body, usage}
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
end
