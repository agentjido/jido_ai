defmodule Jido.AI do
  @moduledoc """
  AI integration layer for the Jido ecosystem.

  Jido.AI provides a unified interface for AI interactions, built on ReqLLM and
  integrated with the Jido action framework.

  ## Features

  - Model aliases for semantic model references
  - Lightweight app-configured LLM defaults
  - Thin ReqLLM generation facades
  - Action-based AI workflows
  - Splode-based error handling

  ## Model Aliases

  Use semantic model aliases instead of hardcoded model strings:

      Jido.AI.resolve_model(:fast)      # => "provider:fast-model"
      Jido.AI.resolve_model(:capable)   # => "provider:capable-model"

  Configure custom aliases in your config:

      config :jido_ai,
        model_aliases: %{
          fast: "provider:your-fast-model",
          capable: "provider:your-capable-model"
        }

  A broad list of provider/model IDs is available at: https://llmdb.xyz

  ## LLM Defaults

  Configure small, role-based defaults for top-level generation helpers:

      config :jido_ai,
        llm_defaults: %{
          text: %{model: :fast, temperature: 0.2, max_tokens: 1024},
          object: %{model: :thinking, temperature: 0.0, max_tokens: 1024},
          stream: %{model: :fast, temperature: 0.2, max_tokens: 1024}
        }

  Then call the facade directly:

      {:ok, response} = Jido.AI.generate_text("Summarize this in one sentence.")
      {:ok, json} = Jido.AI.generate_object("Extract fields", schema)
      {:ok, stream} = Jido.AI.stream_text("Stream this response")

  ## Runtime Tool Management

  Register and unregister tools dynamically with running agents:

      # Register a new tool
      {:ok, agent} = Jido.AI.register_tool(agent_pid, MyApp.Tools.Calculator)

      # Unregister a tool by name
      {:ok, agent} = Jido.AI.unregister_tool(agent_pid, "calculator")

      # List registered tools
      {:ok, tools} = Jido.AI.list_tools(agent_pid)

      # Check if a tool is registered
      {:ok, true} = Jido.AI.has_tool?(agent_pid, "calculator")

  Tools must implement the `Jido.Action` behaviour (`name/0`, `schema/0`, `run/2`).

  """

  alias Jido.Agent.Strategy.State, as: StratState
  alias Jido.AI.ModelAliases
  alias Jido.AI.Turn
  alias ReqLLM.Context

  @type model_alias ::
          :fast | :capable | :thinking | :reasoning | :planning | :image | :embedding | atom()
  @type model_spec :: String.t()
  @type llm_kind :: :text | :object | :stream
  @type llm_generation_opts :: %{
          optional(:model) => model_alias() | model_spec(),
          optional(:system_prompt) => String.t(),
          optional(:max_tokens) => non_neg_integer(),
          optional(:temperature) => number(),
          optional(:timeout) => pos_integer()
        }

  @default_llm_defaults %{
    text: %{
      model: :fast,
      temperature: 0.2,
      max_tokens: 1024,
      timeout: 30_000
    },
    object: %{
      model: :thinking,
      temperature: 0.0,
      max_tokens: 1024,
      timeout: 30_000
    },
    stream: %{
      model: :fast,
      temperature: 0.2,
      max_tokens: 1024,
      timeout: 30_000
    }
  }

  @doc """
  Returns all configured model aliases merged with defaults.

  User overrides from `config :jido_ai, :model_aliases` are merged on top of built-in defaults.

  ## Examples

      iex> aliases = Jido.AI.model_aliases()
      iex> is_binary(aliases[:fast])
      true
  """
  @spec model_aliases() :: %{model_alias() => model_spec()}
  def model_aliases, do: ModelAliases.model_aliases()

  @doc """
  Returns configured LLM generation defaults merged with built-in defaults.

  Configure under `config :jido_ai, :llm_defaults`.
  """
  @spec llm_defaults() :: %{llm_kind() => llm_generation_opts()}
  def llm_defaults do
    configured = Application.get_env(:jido_ai, :llm_defaults, %{})

    Map.merge(@default_llm_defaults, configured, fn _kind, default_opts, configured_opts ->
      if is_map(configured_opts) do
        Map.merge(default_opts, configured_opts)
      else
        default_opts
      end
    end)
  end

  @doc """
  Returns defaults for a specific generation kind: `:text`, `:object`, or `:stream`.
  """
  @spec llm_defaults(llm_kind()) :: llm_generation_opts()
  def llm_defaults(kind) when kind in [:text, :object, :stream] do
    Map.fetch!(llm_defaults(), kind)
  end

  def llm_defaults(kind) do
    raise ArgumentError,
          "Unknown LLM defaults kind: #{inspect(kind)}. " <>
            "Expected one of: :text, :object, :stream"
  end

  @doc """
  Resolves a model alias or passes through a direct model spec.

  Model aliases are atoms like `:fast`, `:capable`, `:reasoning` that map
  to full ReqLLM model specifications. Direct model specs (strings) are
  passed through unchanged.

  ## Arguments

    * `model` - Either a model alias atom or a direct model spec string

  ## Returns

    A ReqLLM model specification string.

  ## Examples

      iex> String.contains?(Jido.AI.resolve_model(:fast), ":")
      true

      iex> Jido.AI.resolve_model("openai:gpt-4")
      "openai:gpt-4"

      Jido.AI.resolve_model(:unknown_alias)
      # raises ArgumentError with unknown alias message
  """
  @spec resolve_model(model_alias() | model_spec()) :: model_spec()
  def resolve_model(model), do: ModelAliases.resolve_model(model)

  @doc """
  Thin facade for `ReqLLM.Generation.generate_text/3`.

  `opts` supports:

  - `:model` - model alias or direct model spec
  - `:system_prompt` - optional system prompt
  - `:max_tokens`, `:temperature`, `:timeout`
  - Any other ReqLLM options (e.g. `:tools`, `:tool_choice`) as pass-through options
  """
  @spec generate_text(term(), keyword()) :: {:ok, term()} | {:error, term()}
  def generate_text(input, opts \\ []) when is_list(opts) do
    defaults = llm_defaults(:text)
    model = resolve_generation_model(opts, defaults)
    system_prompt = Keyword.get(opts, :system_prompt, defaults[:system_prompt])

    with {:ok, req_context} <- normalize_context(input, system_prompt) do
      ReqLLM.Generation.generate_text(model, req_context.messages, build_reqllm_opts(opts, defaults))
    end
  end

  @doc """
  Thin facade for `ReqLLM.Generation.generate_object/4`.

  `opts` has the same behavior as `generate_text/2`.
  """
  @spec generate_object(term(), term(), keyword()) :: {:ok, term()} | {:error, term()}
  def generate_object(input, object_schema, opts \\ []) when is_list(opts) do
    defaults = llm_defaults(:object)
    model = resolve_generation_model(opts, defaults)
    system_prompt = Keyword.get(opts, :system_prompt, defaults[:system_prompt])

    with {:ok, req_context} <- normalize_context(input, system_prompt) do
      ReqLLM.Generation.generate_object(
        model,
        req_context.messages,
        object_schema,
        build_reqllm_opts(opts, defaults)
      )
    end
  end

  @doc """
  Thin facade for `ReqLLM.stream_text/3`.

  Returns ReqLLM stream response directly.
  """
  @spec stream_text(term(), keyword()) :: {:ok, term()} | {:error, term()}
  def stream_text(input, opts \\ []) when is_list(opts) do
    defaults = llm_defaults(:stream)
    model = resolve_generation_model(opts, defaults)
    system_prompt = Keyword.get(opts, :system_prompt, defaults[:system_prompt])

    with {:ok, req_context} <- normalize_context(input, system_prompt) do
      ReqLLM.stream_text(model, req_context.messages, build_reqllm_opts(opts, defaults))
    end
  end

  @doc """
  Convenience helper that returns extracted response text.
  """
  @spec ask(term(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def ask(input, opts \\ []) when is_list(opts) do
    with {:ok, response} <- generate_text(input, opts) do
      {:ok, Turn.extract_text(response)}
    end
  end

  # ============================================================================
  # Tool Management API
  # ============================================================================

  @doc """
  Registers a tool module with a running agent.

  The tool must implement the `Jido.Action` behaviour (have `name/0`, `schema/0`, and `run/2`).

  ## Options

    * `:timeout` - Call timeout in milliseconds (default: 5000)
    * `:validate` - Validate tool implements required callbacks (default: true)

  ## Examples

      {:ok, agent} = Jido.AI.register_tool(agent_pid, MyApp.Tools.Calculator)
      {:error, :not_a_tool} = Jido.AI.register_tool(agent_pid, NotATool)

  """
  @spec register_tool(GenServer.server(), module(), keyword()) ::
          {:ok, Jido.Agent.t()} | {:error, term()}
  def register_tool(agent_server, tool_module, opts \\ []) when is_atom(tool_module) do
    if Keyword.get(opts, :validate, true) do
      with :ok <- validate_tool_module(tool_module) do
        do_register_tool(agent_server, tool_module, opts)
      end
    else
      do_register_tool(agent_server, tool_module, opts)
    end
  end

  @doc """
  Unregisters a tool from a running agent by name.

  ## Options

    * `:timeout` - Call timeout in milliseconds (default: 5000)

  ## Examples

      {:ok, agent} = Jido.AI.unregister_tool(agent_pid, "calculator")

  """
  @spec unregister_tool(GenServer.server(), String.t(), keyword()) ::
          {:ok, Jido.Agent.t()} | {:error, term()}
  def unregister_tool(agent_server, tool_name, opts \\ []) when is_binary(tool_name) do
    timeout = Keyword.get(opts, :timeout, 5000)

    signal =
      Jido.Signal.new!("ai.react.unregister_tool", %{tool_name: tool_name}, source: "/jido/ai")

    case Jido.AgentServer.call(agent_server, signal, timeout) do
      {:ok, agent} -> {:ok, agent}
      {:error, _} = error -> error
    end
  end

  @doc """
  Updates the base ReAct system prompt for a running agent.

  ## Options

    * `:timeout` - Call timeout in milliseconds (default: 5000)

  """
  @spec set_system_prompt(GenServer.server(), String.t(), keyword()) ::
          {:ok, Jido.Agent.t()} | {:error, term()}
  def set_system_prompt(agent_server, prompt, opts \\ []) when is_binary(prompt) do
    timeout = Keyword.get(opts, :timeout, 5000)

    signal =
      Jido.Signal.new!("ai.react.set_system_prompt", %{system_prompt: prompt}, source: "/jido/ai")

    case Jido.AgentServer.call(agent_server, signal, timeout) do
      {:ok, agent} -> {:ok, agent}
      {:error, _} = error -> error
    end
  end

  @doc """
  Steers an active ReAct run with additional user-visible input.

  Returns `{:ok, agent}` when the input is accepted for the active run or
  `{:error, {:rejected, reason}}` when no eligible run is available.

  ## Options

    * `:timeout` - Call timeout in milliseconds (default: 5000)
    * `:expected_request_id` - Optional guard for the currently active request
    * `:source` - Optional source marker recorded with the injected input
    * `:extra_refs` - Optional refs merged into the injected user message

  """
  @spec steer(GenServer.server(), String.t(), keyword()) ::
          {:ok, Jido.Agent.t()} | {:error, term()}
  def steer(agent_server, content, opts \\ []) when is_binary(content) do
    control_agent(agent_server, "ai.react.steer", content, opts, :steer)
  end

  @doc """
  Injects user-visible input into an active ReAct run.

  This is intended for programmatic or inter-agent steering and follows the same
  acceptance rules as `steer/3`.
  """
  @spec inject(GenServer.server(), String.t(), keyword()) ::
          {:ok, Jido.Agent.t()} | {:error, term()}
  def inject(agent_server, content, opts \\ []) when is_binary(content) do
    control_agent(agent_server, "ai.react.inject", content, opts, :inject)
  end

  @doc """
  Lists all currently registered tools for an agent.

  Can be called with either an agent struct or an agent server (PID/name).

  ## Examples

      # With agent struct
      tools = Jido.AI.list_tools(agent)

      # With agent server
      {:ok, tools} = Jido.AI.list_tools(agent_pid)

  """
  @spec list_tools(Jido.Agent.t() | GenServer.server()) ::
          [module()] | {:ok, [module()]} | {:error, term()}
  def list_tools(%Jido.Agent{} = agent) do
    list_tools_from_agent(agent)
  end

  def list_tools(agent_server) do
    case Jido.AgentServer.state(agent_server) do
      {:ok, state} -> {:ok, list_tools(state.agent)}
      {:error, _} = error -> error
    end
  end

  @doc """
  Checks if a specific tool is registered with an agent.

  Can be called with either an agent struct or an agent server (PID/name).

  ## Examples

      # With agent struct
      true = Jido.AI.has_tool?(agent, "calculator")

      # With agent server
      {:ok, true} = Jido.AI.has_tool?(agent_pid, "calculator")

  """
  @spec has_tool?(Jido.Agent.t() | GenServer.server(), String.t()) ::
          boolean() | {:ok, boolean()} | {:error, term()}
  def has_tool?(%Jido.Agent{} = agent, tool_name) when is_binary(tool_name) do
    tools = list_tools(agent)
    Enum.any?(tools, fn mod -> mod.name() == tool_name end)
  end

  def has_tool?(agent_server, tool_name) when is_binary(tool_name) do
    case list_tools(agent_server) do
      {:ok, tools} -> {:ok, Enum.any?(tools, fn mod -> mod.name() == tool_name end)}
      {:error, _} = error -> error
    end
  end

  # ============================================================================
  # Pure-Function (Struct-Level) API
  #
  # These functions operate directly on a %Jido.Agent{} struct without going
  # through GenServer signals. Use these from within the agent process (e.g.,
  # in on_before_cmd / on_after_cmd hooks) where a GenServer.call to self()
  # would deadlock.
  # ============================================================================

  @doc """
  Sets the system prompt directly on the agent's strategy config.

  This is the struct-level equivalent of `set_system_prompt/3` — safe to call
  from within the agent process (e.g., `on_before_cmd`).

  Also updates the system prompt in `:context` and `:run_context` if they
  exist, so resumed conversations pick up the new prompt.
  """
  @spec set_system_prompt_direct(Jido.Agent.t(), String.t()) :: Jido.Agent.t()
  def set_system_prompt_direct(%Jido.Agent{} = agent, prompt) when is_binary(prompt) do
    StratState.update(agent, fn strat_state ->
      config = Map.get(strat_state, :config, %{})
      updated = Map.put(config, :system_prompt, prompt)

      strat_state
      |> Map.put(:config, updated)
      |> update_context_system_prompt(:context, prompt)
      |> update_context_system_prompt(:run_context, prompt)
    end)
  end

  @doc """
  Returns the strategy config from an agent struct.

  Convenience for reading strategy config without reaching into internal state.
  """
  @spec get_strategy_config(Jido.Agent.t()) :: map()
  def get_strategy_config(%Jido.Agent{} = agent) do
    strat_state = StratState.get(agent, %{})
    Map.get(strat_state, :config, %{})
  end

  @doc """
  Returns the active context (conversation history) from the strategy state.

  Prefers `:run_context` while a request is in flight, otherwise falls back to
  materialized `:context`. Returns nil if neither exists.
  """
  @spec get_strategy_context(Jido.Agent.t()) :: map() | nil
  def get_strategy_context(%Jido.Agent{} = agent) do
    strat_state = StratState.get(agent, %{})

    case active_context_key(strat_state) do
      nil -> nil
      key -> Map.get(strat_state, key)
    end
  end

  @doc """
  Updates the active context entries (conversation messages) in the strategy state.

  If `:run_context` exists, it is treated as authoritative for the in-flight
  turn and updated in isolation. Otherwise, updates materialized `:context`.
  """
  @spec update_context_entries(Jido.Agent.t(), list()) :: Jido.Agent.t()
  def update_context_entries(%Jido.Agent{} = agent, entries) when is_list(entries) do
    StratState.update(agent, fn strat_state ->
      case active_context_key(strat_state) do
        nil -> strat_state
        ctx_key -> update_context_field(strat_state, ctx_key, :entries, entries)
      end
    end)
  end

  defp active_context_key(strat_state) when is_map(strat_state) do
    cond do
      is_map(Map.get(strat_state, :run_context)) -> :run_context
      is_map(Map.get(strat_state, :context)) -> :context
      true -> nil
    end
  end

  defp active_context_key(_), do: nil

  # Private: update system_prompt in a context struct if it exists
  defp update_context_system_prompt(strat_state, key, prompt) do
    case Map.get(strat_state, key) do
      %{system_prompt: _} = context ->
        Map.put(strat_state, key, %{context | system_prompt: prompt})

      _ ->
        strat_state
    end
  end

  # Private: update a field in a context struct if the context key exists
  defp update_context_field(strat_state, ctx_key, field, value) do
    case Map.get(strat_state, ctx_key) do
      ctx when is_map(ctx) ->
        Map.put(strat_state, ctx_key, Map.put(ctx, field, value))

      _ ->
        strat_state
    end
  end

  defp control_agent(agent_server, signal_type, content, opts, kind)
       when is_binary(signal_type) and is_binary(content) and kind in [:steer, :inject] do
    timeout = Keyword.get(opts, :timeout, 5_000)

    signal =
      Jido.Signal.new!(
        signal_type,
        %{
          content: content
        }
        |> maybe_put_control_opt(:expected_request_id, Keyword.get(opts, :expected_request_id))
        |> maybe_put_control_opt(:source, Keyword.get(opts, :source, "/jido/ai"))
        |> maybe_put_control_opt(:extra_refs, Keyword.get(opts, :extra_refs)),
        source: "/jido/ai"
      )

    case Jido.AgentServer.call(agent_server, signal, timeout) do
      {:ok, agent} ->
        normalize_control_result(agent, kind)

      {:error, _} = error ->
        error
    end
  end

  defp maybe_put_control_opt(payload, _key, nil), do: payload
  defp maybe_put_control_opt(payload, key, value), do: Map.put(payload, key, value)

  defp normalize_control_result(%Jido.Agent{} = agent, kind) do
    case StratState.get(agent, %{}) |> Map.get(:last_pending_input_control) do
      %{kind: ^kind, status: :accepted} ->
        {:ok, agent}

      %{kind: ^kind, status: :rejected, reason: reason} ->
        {:error, {:rejected, reason}}

      _ ->
        {:error, :unknown_control_result}
    end
  end

  # Private helpers for tool management

  defp do_register_tool(agent_server, tool_module, opts) do
    timeout = Keyword.get(opts, :timeout, 5000)

    signal =
      Jido.Signal.new!("ai.react.register_tool", %{tool_module: tool_module}, source: "/jido/ai")

    case Jido.AgentServer.call(agent_server, signal, timeout) do
      {:ok, agent} -> {:ok, agent}
      {:error, _} = error -> error
    end
  end

  defp validate_tool_module(module) do
    cond do
      not Code.ensure_loaded?(module) ->
        {:error, {:not_loaded, module}}

      not function_exported?(module, :name, 0) ->
        {:error, :not_a_tool}

      not function_exported?(module, :schema, 0) ->
        {:error, :not_a_tool}

      not function_exported?(module, :run, 2) ->
        {:error, :not_a_tool}

      true ->
        :ok
    end
  end

  # Private helpers for top-level LLM facades

  defp resolve_generation_model(opts, defaults) do
    opts
    |> Keyword.get(:model, defaults[:model] || :fast)
    |> resolve_model()
  end

  defp list_tools_from_agent(%Jido.Agent{} = agent) do
    state = StratState.get(agent, %{})
    config = state[:config] || %{}
    config[:tools] || []
  end

  defp normalize_context(input, system_prompt) when system_prompt in [nil, ""] do
    Context.normalize(input)
  end

  defp normalize_context(input, system_prompt) when is_binary(system_prompt) do
    Context.normalize(input, system_prompt: system_prompt)
  end

  defp build_reqllm_opts(opts, defaults) do
    req_opts =
      []
      |> put_opt(:max_tokens, Keyword.get(opts, :max_tokens, defaults[:max_tokens]))
      |> put_opt(:temperature, Keyword.get(opts, :temperature, defaults[:temperature]))
      |> put_timeout_opt(Keyword.get(opts, :timeout, defaults[:timeout]))

    passthrough_opts = Keyword.drop(opts, [:model, :system_prompt, :max_tokens, :temperature, :timeout, :opts])
    extra_opts = Keyword.get(opts, :opts, [])

    req_opts
    |> Keyword.merge(passthrough_opts)
    |> merge_extra_opts(extra_opts)
  end

  defp put_opt(opts, _key, nil), do: opts
  defp put_opt(opts, key, value), do: Keyword.put(opts, key, value)

  defp put_timeout_opt(opts, nil), do: opts
  defp put_timeout_opt(opts, timeout), do: Keyword.put(opts, :receive_timeout, timeout)

  defp merge_extra_opts(opts, extra_opts) when is_list(extra_opts), do: Keyword.merge(opts, extra_opts)
  defp merge_extra_opts(opts, _), do: opts
end
