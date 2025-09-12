defmodule ReqLLM.Providers.OpenAI do
  @moduledoc """
  OpenAI provider implementation using the Provider behavior.

  Supports OpenAI's Chat Completions API with features including:
  - Text generation with GPT models
  - Streaming responses
  - Tool calling
  - Multi-modal inputs (text and images)

  ## Configuration

  Set your OpenAI API key via JidoKeys:

      JidoKeys.put("OPENAI_API_KEY", "your-api-key-here")

  ## Examples

      # Simple text generation
      model = ReqLLM.Model.from("openai:gpt-4")
      {:ok, response} = ReqLLM.generate_text(model, "Hello!")

      # Streaming
      {:ok, stream} = ReqLLM.stream_text(model, "Tell me a story", stream: true)

      # Tool calling
      tools = [%ReqLLM.Tool{name: "get_weather", ...}]
      {:ok, response} = ReqLLM.generate_text(model, "What's the weather?", tools: tools)

  """

  @behaviour ReqLLM.Provider

  import ReqLLM.Provider.Utils,
    only: [prepare_options!: 3, maybe_put: 3, ensure_parsed_body: 1]

  use ReqLLM.Provider.DSL,
    id: :openai,
    base_url: "https://api.openai.com/v1",
    metadata: "priv/models_dev/openai.json",
    default_env_key: "OPENAI_API_KEY",
    context_wrapper: ReqLLM.Providers.OpenAI.Context,
    response_wrapper: ReqLLM.Providers.OpenAI.Response,
    provider_schema: [
      temperature: [type: :float, default: 0.7],
      max_tokens: [type: :pos_integer, default: 1024],
      stream: [type: :boolean, default: false],
      tools: [type: {:list, :map}],
      top_p: [type: :float],
      frequency_penalty: [type: :float],
      presence_penalty: [type: :float],
      stop: [type: {:or, [{:list, :string}, :string]}]
    ]

  @doc """
  Attaches the OpenAI plugin to a Req request.

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
    * All options from ReqLLM.Provider.Options schemas are supported

  """
  @impl ReqLLM.Provider
  def prepare_request(:chat, model_input, %ReqLLM.Context{} = context, opts) do
    with {:ok, model} <- ReqLLM.Model.from(model_input) do
      http_opts = Keyword.get(opts, :req_http_options, [])

      request =
        Req.new([url: "/chat/completions", method: :post, receive_timeout: 30_000] ++ http_opts)
        |> attach(model, Keyword.put(opts, :context, context))

      {:ok, request}
    end
  end

  def prepare_request(operation, _model, _input, _opts) do
    {:error,
     ReqLLM.Error.Invalid.Parameter.exception(
       parameter:
         "operation: #{inspect(operation)} not supported by OpenAI provider. Supported operations: [:chat]"
     )}
  end

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

    api_key_env = ReqLLM.Provider.Registry.get_env_key(:openai)
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
    |> Req.Request.put_header("authorization", "Bearer #{api_key}")
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
          |> ReqLLM.Context.Codec.encode_request()

        _ ->
          %{messages: request.options[:messages] || []}
      end

    tools_data =
      case request.options[:tools] do
        tools when is_list(tools) and length(tools) > 0 ->
          %{tools: Enum.map(tools, &ReqLLM.Schema.to_openai_format/1)}

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
      |> maybe_put(:top_p, request.options[:top_p])
      |> maybe_put(:frequency_penalty, request.options[:frequency_penalty])
      |> maybe_put(:presence_penalty, request.options[:presence_penalty])
      |> maybe_put(:stop, request.options[:stop])

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
            reason: "OpenAI API error",
            status: status,
            response_body: resp.body
          )

        {req, err}
    end
  end
end
