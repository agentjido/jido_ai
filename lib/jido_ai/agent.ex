# credo:disable-for-this-file Credo.Check.Refactor.LongQuoteBlocks

defmodule Jido.AI.Agent do
  @moduledoc """
  Base macro for Jido.AI agents with ReAct strategy implied.

  Wraps `use Jido.Agent` with `Jido.AI.Strategies.ReAct` wired in,
  plus standard state fields and helper functions.

  ## Usage

      defmodule MyApp.WeatherAgent do
        use Jido.AI.Agent,
          name: "weather_agent",
          description: "Weather Q&A agent",
          tools: [MyApp.Actions.Weather, MyApp.Actions.Forecast],
          system_prompt: "You are a weather expert..."
      end

  ## Options

  - `:name` (required) - Agent name
  - `:tools` (required) - List of `Jido.Action` modules to use as tools
  - `:description` - Agent description (default: "AI agent \#{name}")
  - `:tags` - Agent tags for discovery/classification (default: `[]`)
  - `:system_prompt` - Custom system prompt for the LLM
  - `:model` - Model identifier (default: "anthropic:claude-haiku-4-5")
  - `:max_iterations` - Maximum reasoning iterations (default: 10)
  - `:request_policy` - Request concurrency policy (default: `:reject`)
  - `:tool_timeout_ms` - Per-attempt tool execution timeout in ms (default: 15_000)
  - `:tool_max_retries` - Number of retries for tool failures (default: 1)
  - `:tool_retry_backoff_ms` - Retry backoff in ms (default: 200)
  - `:observability` - Observability options map
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

    description = Keyword.get(opts, :description, "AI agent #{name}")
    tags = Keyword.get(opts, :tags, [])
    system_prompt = Keyword.get(opts, :system_prompt)
    model = Keyword.get(opts, :model, @default_model)
    max_iterations = Keyword.get(opts, :max_iterations, @default_max_iterations)
    request_policy = Keyword.get(opts, :request_policy, :reject)
    tool_timeout_ms = Keyword.get(opts, :tool_timeout_ms, 15_000)
    tool_max_retries = Keyword.get(opts, :tool_max_retries, 1)
    tool_retry_backoff_ms = Keyword.get(opts, :tool_retry_backoff_ms, 200)
    observability = Keyword.get(opts, :observability, %{})
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
      [
        tools: tools,
        model: model,
        max_iterations: max_iterations,
        request_policy: request_policy,
        tool_timeout_ms: tool_timeout_ms,
        tool_max_retries: tool_max_retries,
        tool_retry_backoff_ms: tool_retry_backoff_ms,
        observability: observability,
        tool_context: tool_context
      ]
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
      use Jido.Agent,
        name: unquote(name),
        description: unquote(description),
        tags: unquote(tags),
        plugins: unquote(ai_plugins) ++ unquote(plugins),
        strategy: {Jido.AI.Strategies.ReAct, unquote(Macro.escape(strategy_opts))},
        schema: unquote(base_schema_ast)

      unquote(__MODULE__.compatibility_overrides_ast())

      import Jido.AI.Agent, only: [tools_from_skills: 1]

      alias Jido.AI.{Request, Signal}

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
            signal_type: "ai.react.query",
            source: "/ai/react/agent"
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
            signal_type: "ai.react.query",
            source: "/ai/react/agent"
          )
        )
      end

      @impl true
      def on_before_cmd(agent, {:ai_react_start, %{query: query} = params} = action) do
        # Ensure we have a request_id for tracking
        {request_id, params} = Request.ensure_request_id(params)
        action = {:ai_react_start, params}

        # Use RequestTracking to manage state
        agent = Request.start_request(agent, request_id, query)
        emit_request_started_signal(agent, request_id, query)

        {:ok, agent, action}
      end

      @impl true
      def on_before_cmd(
            agent,
            {:ai_react_request_error, %{request_id: request_id, reason: reason, message: message}} = action
          ) do
        agent = Request.fail_request(agent, request_id, {:rejected, reason, message})
        emit_request_failed_signal(agent, request_id, {:rejected, reason, message})
        {:ok, agent, action}
      end

      @impl true
      def on_before_cmd(agent, {:ai_react_cancel, params}) do
        request_id = params[:request_id] || agent.state[:last_request_id]
        action = {:ai_react_cancel, Map.put(params, :request_id, request_id)}
        {:ok, agent, action}
      end

      @impl true
      def on_before_cmd(agent, action), do: {:ok, agent, action}

      @impl true
      def on_after_cmd(agent, {:ai_react_start, %{request_id: request_id}}, directives) do
        snap = strategy_snapshot(agent)

        agent =
          if snap.done? do
            case snap.status do
              :success ->
                agent =
                  Request.complete_request(
                    agent,
                    request_id,
                    snap.result,
                    meta: jido_ai_agent_thinking_meta(snap)
                  )

                emit_request_completed_signal(agent, request_id, snap.result)
                agent

              :failure ->
                reason = failure_reason(snap)
                agent = Request.fail_request(agent, request_id, reason)
                emit_request_failed_signal(agent, request_id, reason)
                agent

              _ ->
                agent
            end
          else
            agent
          end

        {:ok, agent, directives}
      end

      @impl true
      def on_after_cmd(agent, {:ai_react_cancel, %{request_id: request_id, reason: reason}}, directives) do
        agent =
          if is_binary(request_id) do
            failure = {:cancelled, reason}
            emit_request_failed_signal(agent, request_id, failure)
            Request.fail_request(agent, request_id, failure)
          else
            agent
          end

        {:ok, agent, directives}
      end

      @impl true
      def on_after_cmd(agent, {:ai_react_request_error, _params}, directives) do
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
              nil ->
                agent

              request_id ->
                case snap.status do
                  :success ->
                    agent =
                      Request.complete_request(
                        agent,
                        request_id,
                        snap.result,
                        meta: jido_ai_agent_thinking_meta(snap)
                      )

                    emit_request_completed_signal(agent, request_id, snap.result)
                    agent

                  :failure ->
                    reason = failure_reason(snap)
                    agent = Request.fail_request(agent, request_id, reason)
                    emit_request_failed_signal(agent, request_id, reason)
                    agent

                  _ ->
                    agent
                end
            end
          else
            agent
          end

        {:ok, agent, directives}
      end

      # Use a prefixed helper name to avoid collisions with user-defined functions
      # in modules that `use Jido.AI.Agent`.
      defp jido_ai_agent_thinking_meta(snap) do
        details = snap.details
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

      defp failure_reason(snap) do
        details = snap.details

        case details[:termination_reason] do
          :cancelled ->
            {:cancelled, details[:cancel_reason] || :cancelled}

          reason when not is_nil(reason) ->
            {:failed, reason, snap.result}

          _ ->
            {:failed, :unknown, snap.result}
        end
      end

      defp emit_request_started_signal(agent, request_id, query) do
        if lifecycle_signals_enabled?(agent) do
          signal =
            Signal.RequestStarted.new!(%{
              request_id: request_id,
              query: query,
              run_id: request_id
            })

          Jido.AgentServer.cast(self(), signal)
        end
      rescue
        _ -> :ok
      end

      defp emit_request_completed_signal(agent, request_id, result) do
        if lifecycle_signals_enabled?(agent) do
          signal =
            Signal.RequestCompleted.new!(%{
              request_id: request_id,
              result: result,
              run_id: request_id
            })

          Jido.AgentServer.cast(self(), signal)
        end
      rescue
        _ -> :ok
      end

      defp emit_request_failed_signal(agent, request_id, error) do
        if lifecycle_signals_enabled?(agent) do
          signal =
            Signal.RequestFailed.new!(%{
              request_id: request_id,
              error: error,
              run_id: request_id
            })

          Jido.AgentServer.cast(self(), signal)
        end
      rescue
        _ -> :ok
      end

      defp lifecycle_signals_enabled?(agent) do
        get_in(agent.state, [:__strategy__, :config, :observability, :emit_lifecycle_signals?]) != false
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
        reason = Keyword.get(opts, :reason, :user_cancelled)
        request_id = Keyword.get(opts, :request_id)

        payload =
          %{reason: reason}
          |> then(fn p ->
            if is_binary(request_id), do: Map.put(p, :request_id, request_id), else: p
          end)

        signal = Jido.Signal.new!("ai.react.cancel", payload, source: "/ai/react/agent")
        Jido.AgentServer.cast(pid, signal)
      end

      defoverridable on_before_cmd: 2, on_after_cmd: 3, ask: 3, await: 2, ask_sync: 3, cancel: 2
    end
  end

  @doc false
  @spec compatibility_overrides_ast() :: Macro.t()
  def compatibility_overrides_ast do
    quote location: :keep do
      # Broaden the contract to avoid false positives from upstream plugin-spec typing.
      @spec plugin_specs() :: [map()]
      def plugin_specs, do: @plugin_specs

      @impl true
      @spec restore(map(), map()) :: {:ok, Jido.Agent.t()} | {:error, term()}
      def restore(data, ctx) when is_map(data) and is_map(ctx) do
        agent = new(id: data[:id] || data["id"])
        base_state = data[:state] || data["state"] || %{}
        agent = %{agent | state: Map.merge(agent.state, base_state)}
        externalized_keys = data[:externalized_keys] || %{}

        Enum.reduce_while(@plugin_instances, {:ok, agent}, fn instance, {:ok, acc} ->
          config = instance.config || %{}
          restore_ctx = Map.put(ctx, :config, config)

          ext_key =
            Enum.find_value(externalized_keys, fn {k, v} ->
              if v == instance.state_key, do: k
            end)

          pointer = if is_nil(ext_key), do: nil, else: Map.get(data, ext_key)

          if pointer do
            case instance.module.on_restore(pointer, restore_ctx) do
              {:ok, nil} ->
                {:cont, {:ok, acc}}

              {:ok, restored_state} ->
                {:cont, {:ok, %{acc | state: Map.put(acc.state, instance.state_key, restored_state)}}}

              {:error, reason} ->
                {:halt, {:error, reason}}
            end
          else
            {:cont, {:ok, acc}}
          end
        end)
      end

      def restore(_data, _ctx), do: {:error, :invalid_checkpoint_payload}
    end
  end

  @doc """
  Extract tool action modules from skills.

  Useful when you want to use skill actions as agent tools.

  ## Example

      @skills [MyApp.WeatherSkill, MyApp.LocationSkill]

      use Jido.AI.Agent,
        name: "weather_agent",
        tools: Jido.AI.Agent.tools_from_skills(@skills),
        skills: Enum.map(@skills, & &1.skill_spec(%{}))
  """
  @spec tools_from_skills([module()]) :: [module()]
  def tools_from_skills(skill_modules) when is_list(skill_modules) do
    skill_modules
    |> Enum.flat_map(& &1.actions())
    |> Enum.uniq()
  end
end
