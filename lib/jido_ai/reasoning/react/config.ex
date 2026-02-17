defmodule Jido.AI.Reasoning.ReAct.Config do
  @moduledoc """
  Canonical configuration for the Task-based ReAct runtime.
  """

  alias Jido.AI.ToolAdapter
  require Logger

  @default_model :capable
  @default_max_iterations 10
  @legacy_insecure_token_secret "jido_ai_react_default_secret_change_me"
  @ephemeral_secret_key {:jido_ai, __MODULE__, :ephemeral_token_secret}
  @ephemeral_secret_warned_key {:jido_ai, __MODULE__, :ephemeral_token_secret_warned}

  @llm_schema Zoi.object(%{
                max_tokens: Zoi.integer() |> Zoi.default(1_024),
                temperature: Zoi.number() |> Zoi.default(0.2),
                timeout_ms: Zoi.integer() |> Zoi.nullish(),
                tool_choice: Zoi.any() |> Zoi.default(:auto)
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
                          redact_tool_args?: Zoi.boolean() |> Zoi.default(true)
                        })

  @trace_schema Zoi.object(%{
                  capture_deltas?: Zoi.boolean() |> Zoi.default(true),
                  capture_thinking?: Zoi.boolean() |> Zoi.default(true),
                  capture_messages?: Zoi.boolean() |> Zoi.default(true)
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
              model: Zoi.string(description: "Resolved model spec"),
              system_prompt: Zoi.string() |> Zoi.nullish(),
              tools: Zoi.map() |> Zoi.default(%{}),
              max_iterations: Zoi.integer() |> Zoi.default(@default_max_iterations),
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

    tools =
      opts_map
      |> get_opt(:tools, %{})
      |> ToolAdapter.to_action_map()

    llm_timeout = get_opt(opts_map, :llm_timeout_ms, get_opt(opts_map, :timeout_ms, nil))

    llm = %{
      max_tokens: normalize_pos_integer(get_opt(opts_map, :max_tokens, 1_024), 1_024),
      temperature: normalize_float(get_opt(opts_map, :temperature, 0.2), 0.2),
      timeout_ms: normalize_optional_pos_integer(llm_timeout),
      tool_choice: get_opt(opts_map, :tool_choice, :auto)
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
      redact_tool_args?: normalize_boolean(get_opt(opts_map, :redact_tool_args?, true), true)
    }

    trace = %{
      capture_deltas?: normalize_boolean(get_opt(opts_map, :capture_deltas?, true), true),
      capture_thinking?: normalize_boolean(get_opt(opts_map, :capture_thinking?, true), true),
      capture_messages?: normalize_boolean(get_opt(opts_map, :capture_messages?, true), true)
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
      model:
        opts_map
        |> get_opt(:model, @default_model)
        |> resolve_model(),
      system_prompt: normalize_optional_binary(get_opt(opts_map, :system_prompt, nil)),
      tools: tools,
      max_iterations:
        normalize_pos_integer(get_opt(opts_map, :max_iterations, @default_max_iterations), @default_max_iterations),
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
      config.model,
      config.system_prompt || "",
      Integer.to_string(config.max_iterations),
      Integer.to_string(config.tool_exec.timeout_ms),
      Integer.to_string(config.tool_exec.max_retries),
      Integer.to_string(config.tool_exec.retry_backoff_ms),
      Integer.to_string(config.tool_exec.concurrency),
      Enum.join(tool_names, ",")
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
    |> Map.values()
    |> ToolAdapter.from_actions()
  end

  @doc """
  Convert config to generation options for `ReqLLM.Generation.stream_text/3`.
  """
  @spec llm_opts(t()) :: keyword()
  def llm_opts(%__MODULE__{} = config) do
    opts = [
      max_tokens: config.llm.max_tokens,
      temperature: config.llm.temperature,
      tool_choice: config.llm.tool_choice,
      tools: reqllm_tools(config)
    ]

    if is_integer(config.llm.timeout_ms) do
      Keyword.put(opts, :receive_timeout, config.llm.timeout_ms)
    else
      opts
    end
  end

  defp resolve_model(model) when is_binary(model), do: model
  defp resolve_model(model) when is_atom(model), do: Jido.AI.resolve_model(model)
  defp resolve_model(_), do: Jido.AI.resolve_model(@default_model)

  defp normalize_opts(opts) when is_list(opts), do: Map.new(opts)
  defp normalize_opts(opts) when is_map(opts), do: opts
  defp normalize_opts(_), do: %{}

  defp get_opt(map, key, default) when is_map(map) do
    Map.get(map, key, Map.get(map, Atom.to_string(key), default))
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
    if secret == @legacy_insecure_token_secret do
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
end
