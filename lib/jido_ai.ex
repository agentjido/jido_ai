defmodule Jido.AI do
  @moduledoc """
  AI integration layer for the Jido ecosystem.

  Jido.AI adds AI authoring and runtime behavior to normal Jido Agents.
  ReqLLM and LLMDB remain the native model APIs.

  ## Core values and execution

  Use `Jido.AI.Agent` + `Jido.AI.DSL` + `Jido.AI.Profile` to define an AI Agent.
  There is one shared model/tool runtime, including for standalone ReAct.

  - `Jido.AI.Profile` defines the model, tools, limits, and result destination.
  - `Jido.AI.Request` provides handles for individual requests.
  - `Jido.Session` owns one `Jido.Thread` of `Jido.Thread.Entry` values.
    These values belong to this package. They do not own processes.
  - `Jido.AI.Orchestration` is the live request-control API, not a second Session value.
  - `Jido.AI.Tools.Executor` executes tools. `Jido.AI.Model.Response` only represents
    responses and projects messages.

  Internal ownership under lib is:

  ```text
  agent/ + dsl/       authoring and lowering through Profile
  orchestration/     admission, worker lifetime, commit, delivery
  execution/         temporary execution state and shared reasoning Flow
  thread/            AI entry projection and Context controls
  model/             provider transport, options, and message adaptation
  tools/             shared tool execution through core Exec
  ```

  Configuration and Orchestration Plugins install core integration. A Plugin is an
  implementation mechanism; it does not necessarily mean an optional feature.

  ## Optional capabilities

  Reasoning methods, Skills and resources, retrieval, planning, quota services,
  model routing, structured output, tool interception, and Context controls
  attach to the core request path. Portable authoring import/export and the
  standalone ReAct interface are adapters over that path. They do not define
  another Agent or Context store. All eight reasoning methods remain
  supported; resumable tokens are specific to the standalone ReAct adapter.

  ## Model Aliases

  Use semantic model aliases instead of hardcoded model strings:

      Jido.AI.Models.resolve(:fast)      # => "provider:fast-model"
      Jido.AI.Models.resolve(:capable)   # => "provider:capable-model"

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
      Jido.AI.Orchestration.control_agent(
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
      Jido.AI.Orchestration.control_agent(
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

  defp validate_registration(module, opts) do
    if Keyword.get(opts, :validate, true), do: Configuration.validate_tool(module), else: :ok
  end
end
