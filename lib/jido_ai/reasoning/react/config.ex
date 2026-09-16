defmodule Jido.AI.Reasoning.ReAct.Config do
  @moduledoc """
  Configuration for the standalone ReAct adapter over the shared Agent runtime.

  `stream_content`, `store_content`, `stream_reasoning`, `store_reasoning`, and
  `diagnostics_content` use the same default-off permissions as `Jido.AI.Profile`.
  Checkpoint tokens are signed, not encrypted. Automatic token export is
  withheld when its native state cannot satisfy both storage and stream content
  permissions. The live request can still complete. A missing token is reported
  as `:checkpoint_content_not_retained` by `Token.decode/2`; it is not a resumable
  redacted checkpoint.
  """

  alias Jido.AI.Output
  alias Jido.AI.Reasoning.ReAct.RequestTransformer
  alias Jido.AI.ToolAdapter
  require Logger

  @default_model :fast
  @default_max_iterations 10
  @default_max_tokens 4_096
  @insecure_token_secret "jido_ai_react_default_secret_change_me"
  @ephemeral_secret_key {:jido_ai, __MODULE__, :ephemeral_token_secret}
  @ephemeral_secret_warned_key {:jido_ai, __MODULE__, :ephemeral_token_secret_warned}
  @llm_schema Zoi.object(%{
                max_tokens: Zoi.integer() |> Zoi.default(@default_max_tokens),
                temperature: Zoi.number() |> Zoi.default(0.2),
                timeout_ms: Zoi.integer() |> Zoi.nullish(),
                tool_choice: Zoi.any() |> Zoi.default(:auto),
                req_http_options: Zoi.list(Zoi.any()) |> Zoi.default([]),
                llm_opts: Zoi.any() |> Zoi.default([])
              })

  @tool_exec_schema Zoi.object(%{
                      timeout_ms: Zoi.integer() |> Zoi.default(15_000),
                      max_retries: Zoi.integer() |> Zoi.default(1),
                      retry_backoff_ms: Zoi.integer() |> Zoi.default(200),
                      concurrency: Zoi.integer() |> Zoi.default(4)
                    })

  @observability_schema Zoi.object(%{
                          emit_signals?: Zoi.boolean() |> Zoi.default(true),
                          emit_telemetry?: Zoi.boolean() |> Zoi.default(true),
                          redact_tool_args?: Zoi.boolean() |> Zoi.default(true),
                          stream_content: Zoi.boolean() |> Zoi.default(false),
                          store_content: Zoi.boolean() |> Zoi.default(false),
                          stream_reasoning: Zoi.boolean() |> Zoi.default(false),
                          store_reasoning: Zoi.boolean() |> Zoi.default(false),
                          diagnostics_content: Zoi.boolean() |> Zoi.default(false)
                        })

  @trace_schema Zoi.object(%{
                  capture_deltas?: Zoi.boolean() |> Zoi.default(true)
                })

  @token_schema Zoi.object(%{
                  secret: Zoi.string(),
                  ttl_ms: Zoi.integer() |> Zoi.nullish(),
                  compress?: Zoi.boolean() |> Zoi.default(false)
                })

  @schema Zoi.struct(
            __MODULE__,
            %{
              version: Zoi.integer() |> Zoi.default(1),
              model: Zoi.any(description: "Resolved ReqLLM model input"),
              system_prompt: Zoi.string() |> Zoi.nullish(),
              tools: Zoi.map() |> Zoi.default(%{}),
              request_transformer: Zoi.atom() |> Zoi.nullish(),
              pending_input_server: Zoi.any() |> Zoi.nullish(),
              max_iterations: Zoi.integer() |> Zoi.default(@default_max_iterations),
              streaming: Zoi.boolean() |> Zoi.default(true),
              stream_timeout_ms: Zoi.integer() |> Zoi.default(0),
              tool_heartbeat_ms: Zoi.integer() |> Zoi.default(0),
              effect_policy: Zoi.any() |> Zoi.default(%{}),
              output: Zoi.any() |> Zoi.nullish(),
              llm: @llm_schema,
              tool_exec: @tool_exec_schema,
              observability: @observability_schema,
              trace: @trace_schema,
              token: @token_schema
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc false
  def schema, do: @schema

  @doc """
  Build a runtime config from options.
  """
  @spec new(map() | keyword()) :: t()
  def new(opts \\ %{}) do
    opts_map = normalize_opts(opts)
    resolved_model = opts_map |> get_opt(:model, @default_model) |> Jido.AI.Models.resolve()

    tools =
      opts_map
      |> get_opt(:tools, %{})
      |> ToolAdapter.to_action_map()

    output =
      opts_map
      |> get_opt(:output, nil)
      |> Output.new!()

    llm_timeout = get_opt(opts_map, :llm_timeout_ms, nil)

    llm = %{
      max_tokens:
        normalize_pos_integer(
          get_opt(opts_map, :max_tokens, @default_max_tokens),
          @default_max_tokens
        ),
      temperature: normalize_float(get_opt(opts_map, :temperature, 0.2), 0.2),
      timeout_ms: normalize_optional_pos_integer(llm_timeout),
      tool_choice: get_opt(opts_map, :tool_choice, :auto),
      req_http_options: normalize_req_http_options(get_opt(opts_map, :req_http_options, [])),
      llm_opts: Jido.AI.Model.Options.normalize(get_opt(opts_map, :llm_opts, []), resolved_model)
    }

    tool_exec = %{
      timeout_ms: normalize_pos_integer(get_opt(opts_map, :tool_timeout_ms, 15_000), 15_000),
      max_retries: normalize_non_neg_integer(get_opt(opts_map, :tool_max_retries, 1), 1),
      retry_backoff_ms: normalize_non_neg_integer(get_opt(opts_map, :tool_retry_backoff_ms, 200), 200),
      concurrency: normalize_pos_integer(get_opt(opts_map, :tool_concurrency, 4), 4)
    }

    observability = %{
      emit_signals?: normalize_boolean(get_opt(opts_map, :emit_signals?, true), true),
      emit_telemetry?: normalize_boolean(get_opt(opts_map, :emit_telemetry?, true), true),
      redact_tool_args?: normalize_boolean(get_opt(opts_map, :redact_tool_args?, true), true),
      stream_content: normalize_boolean(get_opt(opts_map, :stream_content, false), false),
      store_content: normalize_boolean(get_opt(opts_map, :store_content, false), false),
      stream_reasoning: normalize_boolean(get_opt(opts_map, :stream_reasoning, false), false),
      store_reasoning: normalize_boolean(get_opt(opts_map, :store_reasoning, false), false),
      diagnostics_content: normalize_boolean(get_opt(opts_map, :diagnostics_content, false), false)
    }

    trace = %{
      capture_deltas?: normalize_boolean(get_opt(opts_map, :capture_deltas?, true), true)
    }

    token_secret =
      opts_map
      |> get_opt(:token_secret, Application.get_env(:jido_ai, :react_token_secret))
      |> normalize_token_secret()

    token = %{
      secret: token_secret,
      ttl_ms: normalize_optional_pos_integer(get_opt(opts_map, :token_ttl_ms, nil)),
      compress?: normalize_boolean(get_opt(opts_map, :token_compress?, false), false)
    }

    attrs = %{
      version: 1,
      model: resolved_model,
      system_prompt: normalize_optional_binary(get_opt(opts_map, :system_prompt, nil)),
      tools: tools,
      request_transformer: normalize_request_transformer(get_opt(opts_map, :request_transformer, nil)),
      pending_input_server: get_opt(opts_map, :pending_input_server, nil),
      max_iterations:
        normalize_pos_integer(
          get_opt(opts_map, :max_iterations, @default_max_iterations),
          @default_max_iterations
        ),
      streaming: normalize_boolean(get_opt(opts_map, :streaming, true), true),
      stream_timeout_ms: normalize_non_neg_integer(resolve_stream_timeout_ms(opts_map), 0),
      tool_heartbeat_ms: normalize_non_neg_integer(get_opt(opts_map, :tool_heartbeat_ms, 0), 0),
      effect_policy: get_opt(opts_map, :effect_policy, %{}),
      output: output,
      llm: llm,
      tool_exec: tool_exec,
      observability: observability,
      trace: trace,
      token: token
    }

    case Zoi.parse(@schema, attrs) do
      {:ok, config} -> config
      {:error, errors} -> raise ArgumentError, "invalid ReAct config: #{inspect(errors)}"
    end
  end

  @doc """
  Returns a stable config fingerprint used by checkpoint tokens.
  """
  @spec fingerprint(t()) :: String.t()
  def fingerprint(%__MODULE__{} = config) do
    tool_names = config.tools |> Map.keys() |> Enum.sort()

    parts = [
      "v#{config.version}",
      Jido.AI.Models.fingerprint_segment(config.model),
      config.system_prompt || "",
      Integer.to_string(config.max_iterations),
      to_string(config.streaming),
      Integer.to_string(config.tool_exec.timeout_ms),
      Integer.to_string(config.tool_exec.max_retries),
      Integer.to_string(config.tool_exec.retry_backoff_ms),
      Integer.to_string(config.tool_exec.concurrency),
      Enum.join(tool_names, ","),
      RequestTransformer.fingerprint(config.request_transformer),
      Output.fingerprint(config.output)
    ]

    :crypto.hash(:sha256, Enum.join(parts, "|"))
    |> Base.url_encode64(padding: false)
  end

  @doc """
  Convert runtime tools to ReqLLM tool definitions.
  """
  @spec reqllm_tools(t()) :: [ReqLLM.Tool.t()]
  def reqllm_tools(%__MODULE__{} = config) do
    config.tools
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.map(fn {name, module} -> ToolAdapter.from_action(module, name: name) end)
  end

  @doc """
  Returns the effective stream consumer timeout.

  When `stream_timeout_ms` is 0 (default), auto-derives from
  `tool_exec.timeout_ms + 60_000` to ensure the stream consumer
  outlives the longest possible tool execution plus LLM response time.
  """
  @spec stream_timeout(t()) :: pos_integer()
  def stream_timeout(%__MODULE__{} = config) do
    case config.stream_timeout_ms do
      0 -> config.tool_exec.timeout_ms + 60_000
      ms -> ms
    end
  end

  @doc """
  Returns the tool-execution heartbeat interval in milliseconds.

  When `> 0`, the ReAct runner emits a `:keepalive` event every interval while
  tools are executing, so a consumer that sets a short
  `stream_event_timeout_ms` on `Jido.AI.Request.Stream.events/2` does not time
  out during a long-running tool call. `0` (default) disables heartbeats.
  """
  @spec tool_heartbeat_ms(t()) :: non_neg_integer()
  def tool_heartbeat_ms(%__MODULE__{tool_heartbeat_ms: ms}) when is_integer(ms) and ms >= 0,
    do: ms

  def tool_heartbeat_ms(%__MODULE__{}), do: 0

  @doc """
  Convert config to generation options for `ReqLLM.Generation.stream_text/3`
  and `ReqLLM.Generation.generate_text/3`.
  """
  @spec llm_opts(t()) :: keyword()
  def llm_opts(%__MODULE__{} = config) do
    opts = [
      max_tokens: config.llm.max_tokens,
      temperature: config.llm.temperature,
      tool_choice: config.llm.tool_choice,
      tools: reqllm_tools(config)
    ]

    opts = maybe_merge_llm_opts(opts, config.llm.llm_opts)
    opts = maybe_put_req_http_options(opts, config.llm.req_http_options)

    if is_integer(config.llm.timeout_ms) do
      Keyword.put(opts, :receive_timeout, config.llm.timeout_ms)
    else
      opts
    end
  end

  defp normalize_opts(opts) when is_list(opts), do: Map.new(opts)
  defp normalize_opts(opts) when is_map(opts), do: opts
  defp normalize_opts(_), do: %{}

  defp get_opt(map, key, default) when is_map(map) do
    Map.get(map, key, Map.get(map, Atom.to_string(key), default))
  end

  defp resolve_stream_timeout_ms(opts_map) when is_map(opts_map) do
    get_opt(opts_map, :stream_timeout_ms, 0)
  end

  defp normalize_boolean(value, _default) when is_boolean(value), do: value
  defp normalize_boolean(_value, default), do: default

  defp normalize_pos_integer(value, _default) when is_integer(value) and value > 0, do: value
  defp normalize_pos_integer(_value, default), do: default

  defp normalize_non_neg_integer(value, _default) when is_integer(value) and value >= 0, do: value
  defp normalize_non_neg_integer(_value, default), do: default

  defp normalize_optional_pos_integer(value) when is_integer(value) and value > 0, do: value
  defp normalize_optional_pos_integer(_), do: nil

  defp normalize_float(value, _default) when is_float(value), do: value
  defp normalize_float(value, _default) when is_integer(value), do: value / 1.0
  defp normalize_float(_value, default), do: default

  defp normalize_token_secret(secret) when is_binary(secret) and secret != "" do
    if secret == @insecure_token_secret do
      raise ArgumentError,
            "insecure ReAct token secret rejected; configure :jido_ai, :react_token_secret or pass :token_secret explicitly"
    else
      secret
    end
  end

  defp normalize_token_secret(_), do: ephemeral_token_secret()

  defp ephemeral_token_secret do
    case :persistent_term.get(@ephemeral_secret_key, nil) do
      secret when is_binary(secret) and secret != "" ->
        secret

      _ ->
        secret = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
        :persistent_term.put(@ephemeral_secret_key, secret)
        maybe_warn_ephemeral_secret()
        secret
    end
  end

  defp maybe_warn_ephemeral_secret do
    unless :persistent_term.get(@ephemeral_secret_warned_key, false) do
      :persistent_term.put(@ephemeral_secret_warned_key, true)

      Logger.warning(
        "Jido.AI.Reasoning.ReAct using ephemeral token secret (no configured :react_token_secret); checkpoint tokens expire on VM restart"
      )
    end
  end

  defp normalize_optional_binary(value) when is_binary(value) and value != "", do: value
  defp normalize_optional_binary(_), do: nil

  defp normalize_request_transformer(request_transformer) do
    case RequestTransformer.validate(request_transformer) do
      {:ok, module} ->
        module

      {:error, {:request_transformer_not_loaded, module}} ->
        raise ArgumentError,
              "invalid ReAct request_transformer: module #{inspect(module)} is not loaded"

      {:error, {:request_transformer_missing_callback, module}} ->
        raise ArgumentError,
              "invalid ReAct request_transformer #{inspect(module)}: expected transform_request/4 callback"

      {:error, :invalid_request_transformer} ->
        raise ArgumentError,
              "invalid ReAct request_transformer: expected a module implementing transform_request/4"
    end
  end

  defp normalize_req_http_options(value) when is_list(value), do: value
  defp normalize_req_http_options(_), do: []

  defp maybe_merge_llm_opts(opts, llm_opts) when is_list(llm_opts) do
    if llm_opts == [] do
      opts
    else
      Keyword.merge(opts, llm_opts)
    end
  end

  defp maybe_merge_llm_opts(opts, _), do: opts

  defp maybe_put_req_http_options(opts, req_http_options) when is_list(req_http_options) do
    if req_http_options == [] do
      opts
    else
      Keyword.put(opts, :req_http_options, req_http_options)
    end
  end
end
