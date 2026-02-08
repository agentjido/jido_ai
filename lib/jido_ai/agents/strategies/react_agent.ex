defmodule Jido.AI.ReActAgent do
  @moduledoc """
  Base macro for ReAct-powered agents.

  Wraps `use Jido.Agent` with `Jido.AI.Strategies.ReAct` wired in,
  plus standard state fields and helper functions.

  ## Usage

      defmodule MyApp.WeatherAgent do
        use Jido.AI.ReActAgent,
          name: "weather_agent",
          description: "Weather Q&A agent",
          tools: [MyApp.Actions.Weather, MyApp.Actions.Forecast],
          system_prompt: "You are a weather expert..."
      end

  ## Options

  - `:name` (required) - Agent name
  - `:tools` (required) - List of `Jido.Action` modules to use as tools
  - `:description` - Agent description (default: "ReAct agent \#{name}")
  - `:system_prompt` - Custom system prompt for the LLM
  - `:model` - Model identifier (default: "anthropic:claude-haiku-4-5")
  - `:max_iterations` - Maximum reasoning iterations (default: 10)
  - `:tool_context` - Context map passed to all tool executions (e.g., `%{actor: user, domain: MyDomain}`)
  - `:skills` - Additional skills to attach to the agent (TaskSupervisorSkill is auto-included)

  ## Generated Functions

  - `ask/2,3` - Async: sends query, returns `{:ok, %Request{}}` for later awaiting
  - `await/1,2` - Awaits a specific request's completion
  - `ask_sync/2,3` - Sync convenience: sends query and waits for result
  - `on_before_cmd/2` - Captures request in state before processing
  - `on_after_cmd/3` - Updates request result when done

  ## Request Tracking

  Each `ask/2` call returns a `Request` struct that can be awaited:

      {:ok, request} = MyAgent.ask(pid, "What is 2+2?")
      {:ok, result} = MyAgent.await(request, timeout: 30_000)

  Or use the synchronous convenience wrapper:

      {:ok, result} = MyAgent.ask_sync(pid, "What is 2+2?", timeout: 30_000)

  This pattern follows Elixir's `Task.async/await` idiom and enables safe
  concurrent request handling.

  ## State Fields

  The agent state includes:

  - `:model` - The LLM model being used
  - `:requests` - Map of request_id => request state (for concurrent tracking)
  - `:last_request_id` - ID of the most recent request
  - `:last_query` - The most recent query (backward compat)
  - `:last_answer` - The final answer from the last completed query (backward compat)
  - `:completed` - Boolean indicating if the last query is complete (backward compat)

  ## Task Supervisor

  Each agent instance gets its own Task.Supervisor automatically started via the
  `Jido.AI.Plugins.TaskSupervisor`. This supervisor is used for:
  - LLM streaming operations
  - Tool execution
  - Other async operations within the agent's lifecycle

  The supervisor is stored in the skill's internal state (`agent.state.__task_supervisor_skill__`)
  and is accessible via `Jido.AI.Directive.Helper.get_task_supervisor/1`. It is automatically
  cleaned up when the agent terminates.

  ## Example

      {:ok, pid} = Jido.AgentServer.start(agent: MyApp.WeatherAgent)

      # Async pattern (preferred for concurrent requests)
      {:ok, request} = MyApp.WeatherAgent.ask(pid, "What's the weather in Tokyo?")
      {:ok, answer} = MyApp.WeatherAgent.await(request)

      # Sync pattern (convenience for simple cases)
      {:ok, answer} = MyApp.WeatherAgent.ask_sync(pid, "What's the weather in Tokyo?")

  ## Per-Request Tool Context

  You can pass per-request context that will be merged with the agent's base tool_context:

      {:ok, request} = MyApp.WeatherAgent.ask(pid, "Get my preferences",
        tool_context: %{actor: current_user, tenant_id: "acme"})
  """

  @default_model "anthropic:claude-haiku-4-5"
  @default_max_iterations 10

  @doc false
  def expand_aliases_in_ast(ast, caller_env) do
    Macro.prewalk(ast, fn
      {:__aliases__, _, _} = alias_node ->
        Macro.expand(alias_node, caller_env)

      # Allow literals
      literal when is_atom(literal) or is_binary(literal) or is_number(literal) ->
        literal

      # Allow list syntax
      list when is_list(list) ->
        list

      # Allow map struct syntax: %{...}
      {:%{}, meta, pairs} ->
        {:%{}, meta, pairs}

      # Allow struct syntax: %Module{...}
      {:%, meta, args} ->
        {:%, meta, args}

      # Allow 2-tuples (key-value pairs in maps)
      {key, value} when not is_atom(key) or key not in [:__aliases__, :%, :%{}] ->
        {key, value}

      # Reject function calls and other unsafe constructs
      {func, meta, args} = node when is_atom(func) and is_list(args) ->
        if func in [:__aliases__, :%, :%{}] do
          node
        else
          raise CompileError,
            description:
              "Unsafe construct in tool_context or tools: function call #{inspect(func)} is not allowed. " <>
                "Only module aliases, atoms, strings, numbers, lists, and maps are permitted.",
            line: Keyword.get(meta, :line, 0)
        end

      # Reject module attributes with clear error
      {:@, meta, [{name, _, _}]} ->
        raise CompileError,
          description:
            "Module attributes (@#{name}) are not supported in tool_context, tools, or specialists. " <>
              "Define the value inline or use a compile-time constant.",
          line: Keyword.get(meta, :line, 0)

      # Reject pinned variables
      {:^, meta, _} ->
        raise CompileError,
          description:
            "Pinned variables (^) are not supported in tool_context, tools, or specialists. " <>
              "Use literal values instead.",
          line: Keyword.get(meta, :line, 0)

      other ->
        other
    end)
  end

  defmacro __using__(opts) do
    # Extract all values at compile time (in the calling module's context)
    name = Keyword.fetch!(opts, :name)
    tools_ast = Keyword.fetch!(opts, :tools)

    # Expand module aliases in the tools list to actual module atoms
    # This handles {:__aliases__, _, [...]} tuples from macro expansion
    tools =
      Enum.map(tools_ast, fn
        {:__aliases__, _, _} = alias_ast -> Macro.expand(alias_ast, __CALLER__)
        mod when is_atom(mod) -> mod
      end)

    description = Keyword.get(opts, :description, "ReAct agent #{name}")
    system_prompt = Keyword.get(opts, :system_prompt)
    model = Keyword.get(opts, :model, @default_model)
    max_iterations = Keyword.get(opts, :max_iterations, @default_max_iterations)
    # Don't extract tool_context here - it contains AST with module aliases
    # that need to be evaluated in the calling module's context
    plugins = Keyword.get(opts, :plugins, [])

    # TaskSupervisorSkill is always included for per-instance task supervision
    ai_plugins = [Jido.AI.Plugins.TaskSupervisor]

    # Extract tool_context at macro expansion time
    # Use safe alias-only expansion instead of Code.eval_quoted
    tool_context =
      case Keyword.get(opts, :tool_context) do
        nil ->
          %{}

        {:%, _, _} = map_ast ->
          # It's a struct/map AST - expand aliases safely and evaluate
          expanded_ast = __MODULE__.expand_aliases_in_ast(map_ast, __CALLER__)
          {evaluated, _} = Code.eval_quoted(expanded_ast, [], __CALLER__)
          evaluated

        {:%{}, _, _} = map_ast ->
          # Plain map AST - expand aliases safely and evaluate
          expanded_ast = __MODULE__.expand_aliases_in_ast(map_ast, __CALLER__)
          {evaluated, _} = Code.eval_quoted(expanded_ast, [], __CALLER__)
          evaluated

        other when is_map(other) ->
          other
      end

    strategy_opts =
      [tools: tools, model: model, max_iterations: max_iterations, tool_context: tool_context]
      |> then(fn o -> if system_prompt, do: Keyword.put(o, :system_prompt, system_prompt), else: o end)

    # Build base_schema AST at macro expansion time
    # Includes request tracking fields for concurrent request isolation
    base_schema_ast =
      quote do
        Zoi.object(%{
          __strategy__: Zoi.map() |> Zoi.default(%{}),
          model: Zoi.string() |> Zoi.default(unquote(model)),
          # Request tracking for concurrent request isolation
          requests: Zoi.map() |> Zoi.default(%{}),
          last_request_id: Zoi.string() |> Zoi.optional(),
          # Backward compatibility fields (convenience pointers to most recent)
          last_query: Zoi.string() |> Zoi.default(""),
          last_answer: Zoi.string() |> Zoi.default(""),
          completed: Zoi.boolean() |> Zoi.default(false)
        })
      end

    quote location: :keep do
      use Jido.AI.Agent,
        name: unquote(name),
        description: unquote(description),
        plugins: unquote(ai_plugins) ++ unquote(plugins),
        strategy: {Jido.AI.Strategies.ReAct, unquote(Macro.escape(strategy_opts))},
        schema: unquote(base_schema_ast)

      import Jido.AI.ReActAgent, only: [tools_from_skills: 1]

      alias Jido.AI.Request

      @doc false
      @spec plugin_specs() :: [Jido.Plugin.Spec.t()]
      def plugin_specs, do: super()

      @doc """
      Send a query to the agent asynchronously.

      Returns `{:ok, %Request{}}` immediately. Use `await/2` to wait for the result.

      ## Options

      - `:tool_context` - Additional context map merged with agent's tool_context
      - `:timeout` - Timeout for the underlying cast (default: no timeout)

      ## Examples

          {:ok, request} = MyAgent.ask(pid, "What is 2+2?")
          {:ok, result} = MyAgent.await(request)

      """
      @spec ask(pid() | atom() | {:via, module(), term()}, String.t(), keyword()) ::
              {:ok, Request.Handle.t()} | {:error, term()}
      def ask(pid, query, opts \\ []) when is_binary(query) do
        Request.create_and_send(
          pid,
          query,
          Keyword.merge(opts,
            signal_type: "react.input",
            source: "/react/agent"
          )
        )
      end

      @doc """
      Await the result of a specific request.

      Blocks until the request completes, fails, or times out.

      ## Options

      - `:timeout` - How long to wait in milliseconds (default: 30_000)

      ## Returns

      - `{:ok, result}` - Request completed successfully
      - `{:error, :timeout}` - Request didn't complete in time
      - `{:error, reason}` - Request failed

      ## Examples

          {:ok, request} = MyAgent.ask(pid, "What is 2+2?")
          {:ok, "4"} = MyAgent.await(request, timeout: 10_000)

      """
      @spec await(Request.Handle.t(), keyword()) :: {:ok, any()} | {:error, term()}
      def await(request, opts \\ []) do
        Request.await(request, opts)
      end

      @doc """
      Send a query and wait for the result synchronously.

      Convenience wrapper that combines `ask/3` and `await/2`.

      ## Options

      - `:tool_context` - Additional context map merged with agent's tool_context
      - `:timeout` - How long to wait in milliseconds (default: 30_000)

      ## Examples

          {:ok, result} = MyAgent.ask_sync(pid, "What is 2+2?", timeout: 10_000)

      """
      @spec ask_sync(pid() | atom() | {:via, module(), term()}, String.t(), keyword()) ::
              {:ok, any()} | {:error, term()}
      def ask_sync(pid, query, opts \\ []) when is_binary(query) do
        Request.send_and_await(
          pid,
          query,
          Keyword.merge(opts,
            signal_type: "react.input",
            source: "/react/agent"
          )
        )
      end

      @impl true
      def on_before_cmd(agent, {:react_start, %{query: query} = params} = action) do
        # Ensure we have a request_id for tracking
        {request_id, params} = Request.ensure_request_id(params)
        action = {:react_start, params}

        # Use RequestTracking to manage state
        agent = Request.start_request(agent, request_id, query)

        {:ok, agent, action}
      end

      @impl true
      def on_before_cmd(agent, action), do: {:ok, agent, action}

      @impl true
      def on_after_cmd(agent, {:react_start, %{request_id: request_id}}, directives) do
        snap = strategy_snapshot(agent)

        agent =
          if snap.done? do
            Request.complete_request(agent, request_id, snap.result, meta: thinking_meta(snap))
          else
            agent
          end

        {:ok, agent, directives}
      end

      @impl true
      def on_after_cmd(agent, _action, directives) do
        snap = strategy_snapshot(agent)

        agent =
          if snap.done? do
            agent = %{
              agent
              | state:
                  Map.merge(agent.state, %{
                    last_answer: snap.result || "",
                    completed: true
                  })
            }

            case agent.state[:last_request_id] do
              nil -> agent
              request_id -> Request.complete_request(agent, request_id, snap.result, meta: thinking_meta(snap))
            end
          else
            agent
          end

        {:ok, agent, directives}
      end

      defp thinking_meta(snap) do
        details = snap.details || %{}
        meta = %{}

        meta =
          if details[:thinking_trace] && details[:thinking_trace] != [],
            do: Map.put(meta, :thinking_trace, details[:thinking_trace]),
            else: meta

        meta =
          if details[:streaming_thinking] && details[:streaming_thinking] != "",
            do: Map.put(meta, :last_thinking, details[:streaming_thinking]),
            else: meta

        meta
      end

      @doc """
      Cancel an in-flight request.

      Sends a cancellation signal to the agent. Note that this is advisory -
      the underlying LLM request may still complete.

      ## Options

      - `:reason` - Reason for cancellation (default: :user_cancelled)

      ## Examples

          {:ok, request} = MyAgent.ask(pid, "What is 2+2?")
          :ok = MyAgent.cancel(pid)

      """
      @spec cancel(pid() | atom() | {:via, module(), term()}, keyword()) :: :ok | {:error, term()}
      def cancel(pid, opts \\ []) do
        Jido.cancel(pid, opts)
      end

      defoverridable on_before_cmd: 2, on_after_cmd: 3, ask: 3, await: 2, ask_sync: 3, cancel: 2
    end
  end

  @doc """
  Extract tool action modules from skills.

  Useful when you want to use skill actions as ReAct tools.

  ## Example

      @skills [MyApp.WeatherSkill, MyApp.LocationSkill]

      use Jido.AI.ReActAgent,
        name: "weather_agent",
        tools: Jido.AI.ReActAgent.tools_from_skills(@skills),
        skills: Enum.map(@skills, & &1.skill_spec(%{}))
  """
  @spec tools_from_skills([module()]) :: [module()]
  def tools_from_skills(skill_modules) when is_list(skill_modules) do
    skill_modules
    |> Enum.flat_map(& &1.actions())
    |> Enum.uniq()
  end
end
