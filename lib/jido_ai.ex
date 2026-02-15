defmodule Jido.AI do
  @moduledoc """
  AI integration layer for the Jido ecosystem.

  Jido.AI provides a unified interface for AI interactions, built on ReqLLM and
  integrated with the Jido action framework.

  ## Features

  - Model aliases for semantic model references
  - Action-based AI workflows
  - Splode-based error handling

  ## Model Aliases

  Use semantic model aliases instead of hardcoded model strings:

      Jido.AI.resolve_model(:fast)      # => "anthropic:claude-haiku-4-5"
      Jido.AI.resolve_model(:capable)   # => "anthropic:claude-sonnet-4-20250514"

  Configure custom aliases in your config:

      config :jido_ai,
        model_aliases: %{
          fast: "anthropic:claude-haiku-4-5",
          capable: "anthropic:claude-sonnet-4-20250514"
        }

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

  @type model_alias :: :fast | :capable | :reasoning | :planning | atom()
  @type model_spec :: String.t()

  @default_aliases %{
    fast: "anthropic:claude-haiku-4-5",
    capable: "anthropic:claude-sonnet-4-20250514",
    reasoning: "anthropic:claude-sonnet-4-20250514",
    planning: "anthropic:claude-sonnet-4-20250514"
  }

  @doc """
  Returns all configured model aliases merged with defaults.

  ## Examples

      iex> aliases = Jido.AI.model_aliases()
      iex> aliases[:fast]
      "anthropic:claude-haiku-4-5"
  """
  @spec model_aliases() :: %{model_alias() => model_spec()}
  def model_aliases do
    configured = Application.get_env(:jido_ai, :model_aliases, %{})
    Map.merge(@default_aliases, configured)
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

      iex> Jido.AI.resolve_model(:fast)
      "anthropic:claude-haiku-4-5"

      iex> Jido.AI.resolve_model("openai:gpt-4")
      "openai:gpt-4"

      Jido.AI.resolve_model(:unknown_alias)
      # raises ArgumentError with unknown alias message
  """
  @spec resolve_model(model_alias() | model_spec()) :: model_spec()
  def resolve_model(model) when is_binary(model), do: model

  def resolve_model(model) when is_atom(model) do
    aliases = model_aliases()

    case Map.get(aliases, model) do
      nil ->
        raise ArgumentError,
              "Unknown model alias: #{inspect(model)}. " <>
                "Available aliases: #{inspect(Map.keys(aliases))}"

      spec ->
        spec
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
    Jido.AI.Strategies.ReAct.list_tools(agent)
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
end
