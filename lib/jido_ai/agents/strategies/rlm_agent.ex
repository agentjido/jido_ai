defmodule Jido.AI.RLMAgent do
  @moduledoc """
  Base macro for RLM (Recursive Language Model) agents.

  Wraps `use Jido.Agent` with `Jido.AI.Strategies.RLM` wired in,
  plus standard state fields and helper functions for context exploration.

  ## Usage

      defmodule MyApp.NeedleHaystackAgent do
        use Jido.AI.RLMAgent,
          name: "needle_haystack",
          description: "Finds information in massive text contexts",
          model: "anthropic:claude-sonnet-4-20250514",
          recursive_model: "anthropic:claude-haiku-4-5",
          max_iterations: 15,
          extra_tools: []
      end

  ## Options

  - `:name` (required) - Agent name
  - `:description` - Agent description (default: "RLM agent \#{name}")
  - `:model` - Primary model identifier (default: "anthropic:claude-sonnet-4-20250514")
  - `:recursive_model` - Model for sub-LLM queries (default: "anthropic:claude-haiku-4-5")
  - `:max_iterations` - Maximum exploration iterations (default: 15)
  - `:max_depth` - Maximum recursion depth for agent spawning (default: 0, no spawning)
  - `:child_agent` - Module to use for child agents (default: `Jido.AI.RLM.ChildAgent`)
  - `:extra_tools` - Additional Jido.Action modules beyond RLM exploration tools
  - `:max_children_total` - Tree-wide cap on total spawned child agents (default: nil, unlimited)
  - `:token_budget` - Total token cap across all agents in the tree (default: nil, unlimited)
  - `:resource_ttl_ms` - TTL for auto-cleanup of workspace/context/budget via Reaper (default: nil, disabled)
  - `:auto_spawn?` - Enable runtime-driven auto-chunk → auto-spawn (default: false)
  - `:auto_spawn_threshold_bytes` - Context size threshold for auto-spawn (default: nil)
  - `:parallel_mode` - Orchestration mode: `:llm_driven` (default, existing behavior) or `:runtime` (deterministic chunk→spawn→synthesize, bypasses 2 LLM calls)
  - `:orchestration_mode` - Fan-out tool policy in llm-driven mode: `:auto` (default), `:lua_only`, or `:spawn_only`
  - `:chunk_strategy` - Default chunking strategy for `context_chunk` (`"lines"` or `"bytes"`)
  - `:chunk_size` - Default chunk size for `context_chunk` and runtime prepare phase
  - `:chunk_overlap` - Default chunk overlap for `context_chunk` and runtime prepare phase
  - `:max_chunks` - Default max chunks for `context_chunk` and runtime prepare phase
  - `:chunk_preview_bytes` - Default preview byte size for `context_chunk`
  - `:enforce_chunk_defaults` - When true, force configured chunk defaults onto every `context_chunk` call
  - `:child_max_iterations` - Default child-agent max iterations during runtime/Lua spawn fan-out
  - `:child_timeout` - Default child-agent timeout (ms) during runtime/Lua spawn fan-out
  - `:max_chunk_bytes` - Default max bytes read per chunk during child fan-out
  - `:plugins` - Additional plugins (TaskSupervisorSkill is auto-included)

  ## Generated Functions

  - `explore/3` - Async: sends query + context, returns `{:ok, %Request.Handle{}}`
  - `await/2` - Awaits a specific request's completion
  - `explore_sync/3` - Sync convenience: sends query and waits for result
  - `cancel/2` - Cancel in-flight request
  - `create_workspace/2` - Create an independent workspace, returns `{:ok, workspace_ref}`
  - `delete_workspace/2` - Delete a workspace
  - `load_context/3` - Load context into a store, returns `{:ok, context_ref}`
  - `delete_context/2` - Delete context from store

  ## Workspace & Context Lifecycle

  Workspace and context can be created independently of queries, enabling
  multi-turn exploration and resource reuse:

      # Pre-create workspace and load context
      {:ok, workspace_ref} = MyAgent.create_workspace(pid)
      {:ok, context_ref} = MyAgent.load_context(pid, large_text)

      # Multiple queries reuse the same workspace + context
      {:ok, r1} = MyAgent.explore_sync(pid, "Find X",
        workspace_ref: workspace_ref, context_ref: context_ref)
      {:ok, r2} = MyAgent.explore_sync(pid, "Now find Y",
        workspace_ref: workspace_ref, context_ref: context_ref)

      # Caller manages cleanup
      :ok = MyAgent.delete_context(pid, context_ref)
      :ok = MyAgent.delete_workspace(pid, workspace_ref)

  ## Example

      {:ok, pid} = Jido.AgentServer.start(agent: MyApp.NeedleHaystackAgent)

      {:ok, result} = MyApp.NeedleHaystackAgent.explore_sync(pid,
        "Find the magic number hidden in this text",
        context: massive_text_binary,
        timeout: 300_000
      )
  """

  @default_model "anthropic:claude-sonnet-4-20250514"
  @default_recursive_model "anthropic:claude-haiku-4-5"
  @default_max_iterations 15

  defmacro __using__(opts) do
    resolve_opt = fn value ->
      expanded = Macro.expand(value, __CALLER__)

      case expanded do
        {_, _, _} = ast ->
          try do
            {evaluated, _binding} = Code.eval_quoted(ast, [], __CALLER__)
            evaluated
          rescue
            _ -> expanded
          end

        other ->
          other
      end
    end

    name = opts |> Keyword.fetch!(:name) |> resolve_opt.()
    description = opts |> Keyword.get(:description, "RLM agent #{name}") |> resolve_opt.()
    model = opts |> Keyword.get(:model, @default_model) |> resolve_opt.()
    recursive_model = opts |> Keyword.get(:recursive_model, @default_recursive_model) |> resolve_opt.()
    max_iterations = opts |> Keyword.get(:max_iterations, @default_max_iterations) |> resolve_opt.()
    max_depth = opts |> Keyword.get(:max_depth, 0) |> resolve_opt.()
    child_agent = opts |> Keyword.get(:child_agent, nil) |> resolve_opt.()
    max_children_total = opts |> Keyword.get(:max_children_total, nil) |> resolve_opt.()
    token_budget = opts |> Keyword.get(:token_budget, nil) |> resolve_opt.()
    resource_ttl_ms = opts |> Keyword.get(:resource_ttl_ms, nil) |> resolve_opt.()
    auto_spawn? = opts |> Keyword.get(:auto_spawn?, false) |> resolve_opt.()
    auto_spawn_threshold_bytes = opts |> Keyword.get(:auto_spawn_threshold_bytes, nil) |> resolve_opt.()
    parallel_mode = opts |> Keyword.get(:parallel_mode, :llm_driven) |> resolve_opt.()
    orchestration_mode = opts |> Keyword.get(:orchestration_mode, :auto) |> resolve_opt.()
    chunk_strategy = opts |> Keyword.get(:chunk_strategy, nil) |> resolve_opt.()
    chunk_size = opts |> Keyword.get(:chunk_size, nil) |> resolve_opt.()
    chunk_overlap = opts |> Keyword.get(:chunk_overlap, nil) |> resolve_opt.()
    max_chunks = opts |> Keyword.get(:max_chunks, nil) |> resolve_opt.()
    chunk_preview_bytes = opts |> Keyword.get(:chunk_preview_bytes, nil) |> resolve_opt.()
    enforce_chunk_defaults = opts |> Keyword.get(:enforce_chunk_defaults, false) |> resolve_opt.()
    child_max_iterations = opts |> Keyword.get(:child_max_iterations, nil) |> resolve_opt.()
    child_timeout = opts |> Keyword.get(:child_timeout, nil) |> resolve_opt.()
    max_chunk_bytes = opts |> Keyword.get(:max_chunk_bytes, nil) |> resolve_opt.()
    plugins = opts |> Keyword.get(:plugins, []) |> resolve_opt.()

    extra_tools_ast = opts |> Keyword.get(:extra_tools, []) |> resolve_opt.()

    extra_tools =
      Enum.map(extra_tools_ast, fn
        {:__aliases__, _, _} = alias_ast -> Macro.expand(alias_ast, __CALLER__)
        mod when is_atom(mod) -> mod
      end)

    ai_plugins = [Jido.AI.Plugins.TaskSupervisor]

    strategy_opts = [
      model: model,
      recursive_model: recursive_model,
      max_iterations: max_iterations,
      max_depth: max_depth,
      child_agent: child_agent,
      extra_tools: extra_tools,
      max_children_total: max_children_total,
      token_budget: token_budget,
      resource_ttl_ms: resource_ttl_ms,
      auto_spawn?: auto_spawn?,
      auto_spawn_threshold_bytes: auto_spawn_threshold_bytes,
      parallel_mode: parallel_mode,
      orchestration_mode: orchestration_mode,
      chunk_strategy: chunk_strategy,
      chunk_size: chunk_size,
      chunk_overlap: chunk_overlap,
      max_chunks: max_chunks,
      chunk_preview_bytes: chunk_preview_bytes,
      enforce_chunk_defaults: enforce_chunk_defaults,
      child_max_iterations: child_max_iterations,
      child_timeout: child_timeout,
      max_chunk_bytes: max_chunk_bytes
    ]

    base_schema_ast =
      quote do
        Zoi.object(%{
          __strategy__: Zoi.map() |> Zoi.default(%{}),
          model: Zoi.string() |> Zoi.default(unquote(model)),
          requests: Zoi.map() |> Zoi.default(%{}),
          last_request_id: Zoi.string() |> Zoi.optional(),
          last_query: Zoi.string() |> Zoi.default(""),
          last_answer: Zoi.string() |> Zoi.default(""),
          completed: Zoi.boolean() |> Zoi.default(false)
        })
      end

    quote location: :keep do
      use Jido.Agent,
        name: unquote(name),
        description: unquote(description),
        plugins: unquote(ai_plugins) ++ unquote(plugins),
        strategy: {Jido.AI.Strategies.RLM, unquote(Macro.escape(strategy_opts))},
        schema: unquote(base_schema_ast)

      alias Jido.AI.Request

      @doc """
      Start RLM context exploration asynchronously.

      Returns `{:ok, %Request.Handle{}}` immediately. Use `await/2` to wait for the result.

      ## Options

      - `:context` - The large text context to explore (binary)
      - `:context_ref` - Pre-stored context reference (advanced, alternative to `:context`)
      - `:workspace_ref` - Pre-created workspace reference (enables multi-turn)
      - `:tool_context` - Additional context map merged with agent's tool_context
      - `:timeout` - Timeout for the underlying cast

      ## Examples

          {:ok, request} = MyAgent.explore(pid, "Find the magic number", context: large_text)
          {:ok, result} = MyAgent.await(request)

      """
      @spec explore(pid() | atom() | {:via, module(), term()}, String.t(), keyword()) ::
              {:ok, Request.Handle.t()} | {:error, term()}
      def explore(pid, query, opts \\ []) when is_binary(query) do
        request_id = Keyword.get_lazy(opts, :request_id, fn -> Jido.Signal.ID.generate!() end)
        context = Keyword.get(opts, :context)
        context_ref = Keyword.get(opts, :context_ref)
        tool_context = Keyword.get(opts, :tool_context, %{})

        payload =
          %{query: query, request_id: request_id}
          |> then(fn p -> if context, do: Map.put(p, :context, context), else: p end)
          |> then(fn p -> if context_ref, do: Map.put(p, :context_ref, context_ref), else: p end)
          |> then(fn p ->
            ws_ref = Keyword.get(opts, :workspace_ref)
            if ws_ref, do: Map.put(p, :workspace_ref, ws_ref), else: p
          end)
          |> then(fn p ->
            if map_size(tool_context) > 0, do: Map.put(p, :tool_context, tool_context), else: p
          end)

        signal = Jido.Signal.new!("rlm.explore", payload, source: "/rlm/agent")

        case Jido.AgentServer.cast(pid, signal) do
          :ok ->
            request = Request.Handle.new(request_id, pid, query)
            {:ok, request}

          {:error, _} = error ->
            error
        end
      end

      @doc """
      Await the result of a specific request.

      ## Options

      - `:timeout` - How long to wait in milliseconds (default: 30_000)

      """
      @spec await(Request.Handle.t(), keyword()) :: {:ok, any()} | {:error, term()}
      def await(request, opts \\ []) do
        Request.await(request, opts)
      end

      @doc """
      Start RLM exploration and wait for the result synchronously.

      Convenience wrapper that combines `explore/3` and `await/2`.

      ## Options

      - `:context` - The large text context to explore (binary)
      - `:context_ref` - Pre-stored context reference
      - `:workspace_ref` - Pre-created workspace reference (enables multi-turn)
      - `:tool_context` - Additional context map
      - `:timeout` - How long to wait in milliseconds (default: 30_000)

      ## Examples

          {:ok, result} = MyAgent.explore_sync(pid, "Find the magic number",
            context: large_text, timeout: 300_000)

      """
      @spec explore_sync(pid() | atom() | {:via, module(), term()}, String.t(), keyword()) ::
              {:ok, any()} | {:error, term()}
      def explore_sync(pid, query, opts \\ []) when is_binary(query) do
        timeout = Keyword.get(opts, :timeout, 30_000)

        with {:ok, request} <- explore(pid, query, opts) do
          await(request, timeout: timeout)
        end
      end

      @impl true
      def on_before_cmd(agent, {:rlm_start, %{query: query} = params} = action) do
        {request_id, params} = Request.ensure_request_id(params)
        action = {:rlm_start, params}
        agent = Request.start_request(agent, request_id, query)
        {:ok, agent, action}
      end

      @impl true
      def on_before_cmd(agent, action), do: {:ok, agent, action}

      @impl true
      def on_after_cmd(agent, {:rlm_start, %{request_id: request_id}}, directives) do
        snap = strategy_snapshot(agent)

        agent =
          if snap.done? do
            Request.complete_request(agent, request_id, snap.result)
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
              request_id -> Request.complete_request(agent, request_id, snap.result)
            end
          else
            agent
          end

        {:ok, agent, directives}
      end

      @spec cancel(pid() | atom() | {:via, module(), term()}, keyword()) :: :ok | {:error, term()}
      def cancel(pid, opts \\ []) do
        Jido.cancel(pid, opts)
      end

      @doc """
      Create an independent workspace for exploration state.

      The workspace persists until explicitly deleted, enabling multi-turn
      exploration across multiple `explore/3` calls.

      ## Options

      - `:seed` - Initial workspace state map (default: `%{}`)
      """
      @spec create_workspace(pid() | atom() | {:via, module(), term()}, keyword()) ::
              {:ok, Jido.AI.RLM.WorkspaceStore.workspace_ref()} | {:error, term()}
      def create_workspace(pid, opts \\ []) do
        seed = Keyword.get(opts, :seed, %{})
        request_id = Jido.Signal.ID.generate!()

        {:ok, workspace_ref} = Jido.AI.RLM.WorkspaceStore.init(request_id, seed)
        {:ok, workspace_ref}
      end

      @doc """
      Delete a workspace and free its resources.
      """
      @spec delete_workspace(pid() | atom() | {:via, module(), term()}, Jido.AI.RLM.WorkspaceStore.workspace_ref()) ::
              :ok
      def delete_workspace(_pid, workspace_ref) do
        Jido.AI.RLM.WorkspaceStore.delete(workspace_ref)
      end

      @doc """
      Load context into a store and return a reference.

      The context persists until explicitly deleted, enabling reuse across
      multiple queries without re-storing.

      ## Options

      - `:workspace_ref` - Associate context with a workspace for co-located storage
      - `:inline_threshold` - Byte threshold for inline vs ETS storage (default: 2MB)
      """
      @spec load_context(pid() | atom() | {:via, module(), term()}, binary(), keyword()) ::
              {:ok, Jido.AI.RLM.ContextStore.context_ref()} | {:error, term()}
      def load_context(_pid, context, opts \\ []) when is_binary(context) do
        request_id = Jido.Signal.ID.generate!()
        workspace_ref = Keyword.get(opts, :workspace_ref)
        inline_threshold = Keyword.get(opts, :inline_threshold, 2_000_000)

        store_opts = [inline_threshold: inline_threshold]
        store_opts = if workspace_ref, do: Keyword.put(store_opts, :workspace_ref, workspace_ref), else: store_opts

        Jido.AI.RLM.ContextStore.put(context, request_id, store_opts)
      end

      @doc """
      Delete context and free its resources.
      """
      @spec delete_context(pid() | atom() | {:via, module(), term()}, Jido.AI.RLM.ContextStore.context_ref()) ::
              :ok
      def delete_context(_pid, context_ref) do
        Jido.AI.RLM.ContextStore.delete(context_ref)
      end

      defoverridable on_before_cmd: 2,
                     on_after_cmd: 3,
                     explore: 3,
                     await: 2,
                     explore_sync: 3,
                     cancel: 2,
                     create_workspace: 2,
                     delete_workspace: 2,
                     load_context: 3,
                     delete_context: 2
    end
  end
end
