defmodule Jido.AI do
  @moduledoc """
  AI integration layer for the Jido ecosystem.

  Jido.AI adds AI authoring and runtime behavior to normal Jido Agents.
  ReqLLM and LLMDB remain the native model APIs.

  ## Features

  - Model aliases for semantic model references
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

  Aliases can also point at full direct model specs when you need richer
  ReqLLM metadata, such as a custom OpenAI-compatible `base_url`:

      config :jido_ai,
        model_aliases: %{
          capable: %{
            provider: :openai,
            id: "moonshotai.kimi-k2.5",
            base_url: "https://proxy.example.com/v1"
          }
        }

  A broad list of provider/model IDs is available at: https://llmcatalog.dev

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

  import Kernel, except: [inspect: 1]

  alias Jido.AI.Models

  @doc "Builds one canonical, validated AI profile."
  def profile(attrs, opts \\ []), do: Jido.AI.Profile.new(attrs, opts)

  @doc "Builds one canonical AI profile or raises its Splode validation error."
  def profile!(attrs, opts \\ []), do: Jido.AI.Profile.new!(attrs, opts)

  @doc "Returns a safe canonical view of an Agent's AI profiles."
  def inspect(source, opts \\ []), do: Jido.AI.Portable.inspect(source, opts)

  @doc "Resolves an AI request plan without a provider or tool call."
  def preflight(source, request, opts \\ []), do: Jido.AI.Portable.preflight(source, request, opts)

  @doc "Exports an Agent or Profile as a versioned map, JSON, or YAML document."
  def export(source, format, opts \\ []), do: Jido.AI.Portable.export(source, format, opts)

  @doc "Imports a versioned map, JSON, or YAML document through explicit registries."
  def import(input, opts \\ []), do: Jido.AI.Portable.import(input, opts)

  @type model_alias :: atom()
  @type model_spec :: String.t()
  @type model_input :: model_alias() | ReqLLM.model_input()
  @doc """
  Returns all configured model aliases.

  Application aliases are merged over the package baseline from `config/config.exs`.

  ## Examples

      iex> aliases = Jido.AI.model_aliases()
      iex> is_binary(aliases[:fast])
      true
  """
  @spec model_aliases() :: %{model_alias() => ReqLLM.model_input()}
  def model_aliases, do: Models.aliases()

  @doc """
  Resolves a model alias or passes through a direct ReqLLM model input.

  Model aliases are atoms like `:fast`, `:capable`, `:reasoning` that map
  to full ReqLLM model specifications. Both alias values and direct model
  inputs may be strings, ReqLLM tuples, inline maps, or `%LLMDB.Model{}`
  structs.

  ## Arguments

    * `model` - Either a model alias atom or a direct ReqLLM model input

  ## Returns

    A resolved ReqLLM model input.

  ## Examples

      iex> String.contains?(Jido.AI.resolve_model(:fast), ":")
      true

      iex> Jido.AI.resolve_model("openai:gpt-4")
      "openai:gpt-4"

      iex> Jido.AI.resolve_model({:openai, "gpt-4.1", []})
      {:openai, "gpt-4.1", []}

      Jido.AI.resolve_model(:unknown_alias)
      # raises ArgumentError with unknown alias message
  """
  @spec resolve_model(model_input()) :: ReqLLM.model_input()
  def resolve_model(model), do: Models.resolve(model)

  alias Jido.AI.Configuration

  @doc "Registers an Action for later requests. Options: timeout, validate and profile."
  @spec register_tool(GenServer.server(), module(), keyword()) ::
          {:ok, Jido.Agent.t()} | {:error, term()}
  def register_tool(server, module, opts \\ []) when is_atom(module) do
    with :ok <- validate_registration(module, opts),
         do: Configuration.live(server, :register, module, opts)
  end

  @doc "Removes a public tool name from later requests."
  @spec unregister_tool(GenServer.server(), String.t(), keyword()) ::
          {:ok, Jido.Agent.t()} | {:error, term()}
  def unregister_tool(server, name, opts \\ []) when is_binary(name),
    do: Configuration.live(server, :unregister, name, opts)

  @doc "Changes the base prompt for later requests; empty text removes it."
  @spec set_system_prompt(GenServer.server(), String.t(), keyword()) ::
          {:ok, Jido.Agent.t()} | {:error, term()}
  def set_system_prompt(server, text, opts \\ []) when is_binary(text),
    do: Configuration.live(server, :prompt, text, opts)

  @doc "Replaces the base tool context for later requests. Values must be portable."
  @spec set_tool_context(GenServer.server(), map(), keyword()) :: {:ok, Jido.Agent.t()} | {:error, term()}
  def set_tool_context(server, context, opts \\ []),
    do: Configuration.live(server, :tool_context, context, opts)

  @doc "Replaces the base tool context on an Agent value without a Server call."
  @spec set_tool_context_direct(Jido.Agent.t(), map(), keyword()) :: {:ok, Jido.Agent.t()} | {:error, term()}
  def set_tool_context_direct(%Jido.Agent{} = agent, context, opts \\ []),
    do: Configuration.direct(agent, :tool_context, context, opts)

  @doc "Queues visible input for an active request and returns the Agent."
  @spec steer(GenServer.server(), String.t(), keyword()) ::
          {:ok, Jido.Agent.t()} | {:error, term()}
  def steer(server, content, opts \\ []) when is_binary(content),
    do:
      Jido.AI.Session.control_agent(
        server,
        content,
        :steer,
        Keyword.put_new(opts, :source, "/jido/ai")
      )

  @doc "Queues peer input for an active request and returns the Agent."
  @spec inject(GenServer.server(), String.t(), keyword()) ::
          {:ok, Jido.Agent.t()} | {:error, term()}
  def inject(server, content, opts \\ []) when is_binary(content),
    do:
      Jido.AI.Session.control_agent(
        server,
        content,
        :inject,
        Keyword.put_new(opts, :source, "/jido/ai")
      )

  @doc "Lists current tool targets on an Agent value, or returns a tagged list from a Server."
  @spec list_tools(Jido.Agent.t() | GenServer.server()) ::
          list() | {:ok, list()} | {:error, term()}
  def list_tools(%Jido.Agent{} = agent) do
    case Configuration.profile(agent) do
      {:ok, profile} -> Enum.map(profile.tools, & &1.target)
      {:error, _} -> []
    end
  end

  def list_tools(server), do: {:ok, list_tools(Jido.AgentServer.agent(server))}

  @doc "Checks the current public tool name, including a native alias."
  @spec has_tool?(Jido.Agent.t() | GenServer.server(), String.t()) ::
          boolean() | {:ok, boolean()} | {:error, term()}
  def has_tool?(%Jido.Agent{} = agent, name) when is_binary(name) do
    case Configuration.profile(agent) do
      {:ok, profile} -> Enum.any?(profile.tools, &(&1.name == name))
      {:error, _} -> false
    end
  end

  def has_tool?(server, name) when is_binary(name),
    do: {:ok, has_tool?(Jido.AgentServer.agent(server), name)}

  @doc "Registers an Action on an Agent value without a Server call."
  @spec register_tool_direct(Jido.Agent.t(), module(), keyword()) ::
          {:ok, Jido.Agent.t()} | {:error, term()}
  def register_tool_direct(%Jido.Agent{} = agent, module, opts \\ []) when is_atom(module) do
    with :ok <- validate_registration(module, opts),
         do: Configuration.direct(agent, :register, module, opts)
  end

  @doc "Removes a public tool name on an Agent value without a Server call."
  @spec unregister_tool_direct(Jido.Agent.t(), String.t()) ::
          {:ok, Jido.Agent.t()} | {:error, term()}
  def unregister_tool_direct(%Jido.Agent{} = agent, name) when is_binary(name),
    do: Configuration.direct(agent, :unregister, name)

  @doc "Changes the prompt on an Agent value without a Server call."
  @spec set_system_prompt_direct(Jido.Agent.t(), String.t()) :: Jido.Agent.t()
  def set_system_prompt_direct(%Jido.Agent{} = agent, text) when is_binary(text) do
    case Configuration.direct(agent, :prompt, text) do
      {:ok, next} -> next
      {:error, error} when is_exception(error) -> raise error
      {:error, error} -> raise ArgumentError, Kernel.inspect(error)
    end
  end

  @doc "Returns a compatibility view of the effective profile configuration."
  @spec get_strategy_config(Jido.Agent.t()) :: map()
  def get_strategy_config(agent), do: get_strategy_config(agent, nil)

  @doc "Returns current configuration for one declared AI profile."
  def get_strategy_config(%Jido.Agent{} = agent, profile_id) do
    case Configuration.profile(agent, profile_id) do
      {:ok, profile} ->
        entry = profile.models[profile.reasoning.model]

        Map.get(profile.reasoning, :options, %{})
        |> Map.merge(Map.new(entry.generation))
        |> Map.merge(%{
          model: entry.model,
          system_prompt: profile.instructions,
          base_tool_context: profile.tool_context,
          tools: Enum.map(profile.tools, & &1.target),
          actions_by_name: Map.new(profile.tools, &{&1.name, &1.target}),
          reqllm_tools: Jido.AI.ToolCatalog.definitions(profile.tools),
          max_iterations: profile.controls.max_iterations,
          max_tool_calls: profile.controls.max_tool_calls,
          request_policy: profile.requests.on_busy,
          streaming: profile.requests.streaming
        })

      {:error, _} ->
        %{}
    end
  end

  @doc "Returns committed domain history as an AI Context; active private work remains runtime-owned."
  @spec get_strategy_context(Jido.Agent.t()) :: Jido.AI.Context.t() | nil
  def get_strategy_context(agent), do: get_strategy_context(agent, nil)

  @doc "Returns committed Context for one declared AI profile."
  def get_strategy_context(%Jido.Agent{} = agent, profile_id) do
    with {:ok, profile} <- Configuration.profile(agent, profile_id),
         false <- is_nil(profile.memory.history),
         {:ok, entries} <- Jido.AI.History.read(agent.state, profile) do
      Jido.AI.Context.new(id: "#{agent.id}:#{profile.id}", system_prompt: profile.instructions)
      |> Jido.AI.Context.append_messages(entries)
    else
      _ -> nil
    end
  end

  @doc "Replaces committed history using Context's reverse entry order; already-started work keeps its snapshot."
  @spec update_context_entries(Jido.Agent.t(), list()) :: Jido.Agent.t()
  def update_context_entries(%Jido.Agent{} = agent, entries) when is_list(entries) do
    with {:ok, profile} <- Configuration.profile(agent),
         false <- is_nil(profile.memory.history) do
      case Jido.AI.History.replace(agent, profile, entries) do
        {:ok, next} -> next
        {:error, error} when is_exception(error) -> raise error
        {:error, error} -> raise ArgumentError, Kernel.inspect(error)
      end
    else
      _ -> agent
    end
  end

  defp validate_registration(module, opts) do
    if Keyword.get(opts, :validate, true), do: Configuration.validate_tool(module), else: :ok
  end
end
