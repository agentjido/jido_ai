defmodule ReqLLM.Providers.Groq do
  @moduledoc """
  Groq provider implementation using the Provider behavior.

  Groq provides fast LLM inference with OpenAI-compatible API endpoints.
  It offers high-performance inference for various open-source models.

  ## Configuration

  Set your Groq API key via environment variable:

      export GROQ_API_KEY="your-api-key-here"

  ## Examples

      # Simple text generation
      model = ReqLLM.Model.from("groq:llama3-8b-8192")
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
    id: :groq,
    base_url: "https://api.groq.com/openai/v1",
    metadata: "priv/models_dev/groq.json",
    default_env_key: "GROQ_API_KEY",
    context_wrapper: ReqLLM.Providers.Groq.Context,
    response_wrapper: ReqLLM.Providers.Groq.Response,
    provider_schema: [
      temperature: [type: :float, default: 0.7],
      max_tokens: [type: :pos_integer, default: 1024],
      top_p: [type: :float],
      stream: [type: :boolean, default: false],
      system: [type: :string],
      tools: [type: {:list, :map}],
      tool_choice: [type: {:or, [:string, :map]}],
      response_format: [type: :map],
      frequency_penalty: [type: :float],
      presence_penalty: [type: :float],
      logit_bias: [type: :map],
      user: [type: :string],
      service_tier: [type: :string],
      reasoning_effort: [type: :string],
      reasoning_format: [type: :string],
      search_settings: [type: :map],
      compound_custom: [type: :map],
      seed: [type: :pos_integer]
    ]

  @doc """
  Attaches the Groq plugin to a Req request.

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
    * `:service_tier` - Performance tier (auto, on_demand, flex, performance)
    * `:reasoning_effort` - Reasoning effort level (none, default, low, medium, high)
    * `:reasoning_format` - Format for reasoning output
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
         "operation: #{inspect(operation)} not supported by Groq provider. Supported operations: [:chat]"
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

    api_key_env = ReqLLM.Provider.Registry.get_env_key(:groq)
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
    # Groq uses Bearer token authentication
    |> Req.Request.merge_options(
      Keyword.take(opts, req_keys) ++ [base_url: base_url, auth: {:bearer, api_key}]
    )
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

  # Parameter validation helpers
  defp validate_parameter_ranges(opts) do
    with :ok <- validate_temperature(opts[:temperature]),
         :ok <- validate_top_p(opts[:top_p]),
         :ok <- validate_max_tokens(opts[:max_tokens]),
         :ok <- validate_frequency_penalty(opts[:frequency_penalty]),
         :ok <- validate_presence_penalty(opts[:presence_penalty]),
         :ok <- validate_service_tier(opts[:service_tier]),
         :ok <- validate_reasoning_effort(opts[:reasoning_effort]) do
      :ok
    end
  end

  defp validate_temperature(nil), do: :ok
  defp validate_temperature(temp) when is_number(temp) and temp >= 0.0 and temp <= 2.0, do: :ok

  defp validate_temperature(temp),
    do: {:error, "temperature must be between 0.0 and 2.0, got #{temp}"}

  defp validate_top_p(nil), do: :ok
  defp validate_top_p(top_p) when is_number(top_p) and top_p > 0.0 and top_p <= 1.0, do: :ok
  defp validate_top_p(top_p), do: {:error, "top_p must be between 0.0 and 1.0, got #{top_p}"}

  defp validate_max_tokens(nil), do: :ok

  defp validate_max_tokens(max_tokens)
       when is_integer(max_tokens) and max_tokens >= 1,
       do: :ok

  defp validate_max_tokens(max_tokens),
    do: {:error, "max_tokens must be >= 1, got #{max_tokens}"}

  defp validate_frequency_penalty(nil), do: :ok

  defp validate_frequency_penalty(penalty)
       when is_number(penalty) and penalty >= -2.0 and penalty <= 2.0,
       do: :ok

  defp validate_frequency_penalty(penalty),
    do: {:error, "frequency_penalty must be between -2.0 and 2.0, got #{penalty}"}

  defp validate_presence_penalty(nil), do: :ok

  defp validate_presence_penalty(penalty)
       when is_number(penalty) and penalty >= -2.0 and penalty <= 2.0,
       do: :ok

  defp validate_presence_penalty(penalty),
    do: {:error, "presence_penalty must be between -2.0 and 2.0, got #{penalty}"}

  defp validate_service_tier(nil), do: :ok

  defp validate_service_tier(tier) when tier in ~w(auto on_demand flex performance),
    do: :ok

  defp validate_service_tier(tier),
    do: {:error, "service_tier must be one of: auto, on_demand, flex, performance, got #{tier}"}

  defp validate_reasoning_effort(nil), do: :ok

  defp validate_reasoning_effort(effort) when effort in ~w(none default low medium high),
    do: :ok

  defp validate_reasoning_effort(effort),
    do:
      {:error, "reasoning_effort must be one of: none, default, low, medium, high, got #{effort}"}

  # Req pipeline steps
  @impl ReqLLM.Provider
  def encode_body(request) do
    # Validate parameter ranges before proceeding
    case validate_parameter_ranges(request.options) do
      :ok ->
        nil

      {:error, reason} ->
        raise ReqLLM.Error.Invalid.Parameter.exception(parameter: reason)
    end

    context_data =
      case request.options[:context] do
        %ReqLLM.Context{} = ctx ->
          ctx
          |> wrap_context()
          |> ReqLLM.Context.Codec.encode_request()

        _ ->
          %{messages: request.options[:messages] || []}
      end

    # Get the model name (Groq uses model names like "llama3-8b-8192")
    model = request.options[:model]
    model_name = if is_struct(model, ReqLLM.Model), do: model.model, else: model

    body =
      %{model: model_name}
      |> Map.merge(context_data)
      |> maybe_put(:temperature, request.options[:temperature])
      |> maybe_put(:max_tokens, request.options[:max_tokens])
      |> maybe_put(:top_p, request.options[:top_p])
      |> maybe_put(:stream, request.options[:stream])
      |> maybe_put(:frequency_penalty, request.options[:frequency_penalty])
      |> maybe_put(:presence_penalty, request.options[:presence_penalty])
      |> maybe_put(:logit_bias, request.options[:logit_bias])
      |> maybe_put(:user, request.options[:user])
      |> maybe_put(:service_tier, request.options[:service_tier])
      |> maybe_put(:reasoning_effort, request.options[:reasoning_effort])
      |> maybe_put(:reasoning_format, request.options[:reasoning_format])
      |> maybe_put(:search_settings, request.options[:search_settings])
      |> maybe_put(:compound_custom, request.options[:compound_custom])
      |> maybe_put(:seed, request.options[:seed])

    # Handle tools if provided
    body =
      case request.options[:tools] do
        tools when is_list(tools) and length(tools) > 0 ->
          body = Map.put(body, :tools, Enum.map(tools, &ReqLLM.Tool.to_schema(&1, :openai)))

          # Handle tool_choice if provided
          case request.options[:tool_choice] do
            nil -> body
            choice -> Map.put(body, :tool_choice, choice)
          end

        _ ->
          body
      end

    # Handle response format if provided
    body =
      case request.options[:response_format] do
        format when is_map(format) ->
          Map.put(body, :response_format, format)

        _ ->
          body
      end

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
            reason: "Groq API error",
            status: status,
            response_body: resp.body
          )

        {req, err}
    end
  end
end
