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

  import ReqLLM.Provider.Utils,
    only: [prepare_options!: 3, maybe_put: 3, ensure_parsed_body: 1, get_env_key: 1]

  use ReqLLM.Provider.DSL,
    id: :anthropic,
    base_url: "https://api.anthropic.com/v1",
    metadata: "priv/models_dev/anthropic.json",
    default_env_key: "ANTHROPIC_API_KEY",
    context_wrapper: ReqLLM.Providers.Anthropic.Context,
    response_wrapper: ReqLLM.Providers.Anthropic.Response,
    provider_schema: [
      temperature: [type: :float, default: 0.7],
      max_tokens: [type: :pos_integer, default: 1024],
      top_p: [type: :float],
      top_k: [type: :pos_integer],
      stream: [type: :boolean, default: false],
      stop_sequences: [type: {:list, :string}],
      system: [type: :string],
      api_version: [type: :string, default: "2023-06-01"],
      tools: [type: {:list, :map}]
    ]

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

    api_key_env = get_env_key(:anthropic)
    api_key = JidoKeys.get(api_key_env)

    unless api_key && api_key != "" do
      raise ReqLLM.Error.Invalid.Parameter.exception(
              parameter: "api_key (set via JidoKeys.put(#{inspect(api_key_env)}, key))"
            )
    end

    # Extract tools separately to avoid validation issues
    {tools, other_opts} = Keyword.pop(user_opts, :tools, [])

    # Prepare validated options and extract what Req needs
    opts = prepare_options!(__MODULE__, model, other_opts)

    # Add tools back after validation
    opts = Keyword.put(opts, :tools, tools)
    base_url = Keyword.get(user_opts, :base_url, default_base_url())
    req_keys = __MODULE__.supported_provider_options() ++ [:model, :context]

    request
    |> Req.Request.register_options(req_keys)
    |> Req.Request.merge_options(Keyword.take(opts, req_keys) ++ [base_url: base_url])
    |> Req.Request.put_header("x-api-key", api_key)
    |> Req.Request.put_header("anthropic-version", opts[:api_version] || @default_api_version)
    |> ReqLLM.Step.Error.attach()
    |> Req.Request.append_request_steps(llm_encode_body: &__MODULE__.encode_body/1)
    |> ReqLLM.Step.Stream.maybe_attach(opts[:stream])
    |> Req.Request.append_response_steps(llm_decode_response: &__MODULE__.decode_response/1)
    |> ReqLLM.Step.Usage.attach(model)
  end

  @impl ReqLLM.Provider
  def extract_usage(body, _model) when is_map(body) do
    case body do
      %{"usage" => usage} -> {:ok, usage}
      _ -> {:error, :no_usage_found}
    end
  end

  def extract_usage(_, _), do: {:error, :invalid_body}

  # Req pipeline steps
  @impl ReqLLM.Provider
  def encode_body(request) do
    context_data =
      case request.options[:context] do
        %ReqLLM.Context{} = ctx ->
          ctx
          |> wrap_context()
          |> ReqLLM.Context.Codec.encode()

        _ ->
          %{messages: request.options[:messages] || []}
      end

    tools_data =
      case request.options[:tools] do
        tools when is_list(tools) and length(tools) > 0 ->
          %{tools: Enum.map(tools, &ReqLLM.Tool.to_schema(&1, :anthropic))}

        _ ->
          %{}
      end

    body =
      %{
        model: request.options[:model] || request.options[:id],
        temperature: request.options[:temperature],
        max_tokens: request.options[:max_tokens],
        stream: request.options[:stream]
      }
      |> Map.merge(context_data)
      |> Map.merge(tools_data)
      |> maybe_put(:system, request.options[:system])

    try do
      encoded_body = Jason.encode!(body)

      request
      |> Req.Request.put_header("content-type", "application/json")
      |> Map.put(:body, encoded_body)
    rescue
      error ->
        reraise error, __STACKTRACE__
    end
  end

  @impl ReqLLM.Provider
  def decode_response({req, resp}) do
    case resp.status do
      200 ->
        body = ensure_parsed_body(resp.body)
        # Return raw parsed data directly - no wrapping needed
        {req, %{resp | body: body}}

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
end
