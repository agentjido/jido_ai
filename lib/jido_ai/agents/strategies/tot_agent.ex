# credo:disable-for-this-file Credo.Check.Refactor.LongQuoteBlocks

defmodule Jido.AI.ToTAgent do
  @moduledoc """
  Base macro for Tree-of-Thoughts-powered agents.

  Wraps `use Jido.Agent` with `Jido.AI.Strategies.TreeOfThoughts` wired in,
  plus standard state fields and helper functions.

  ## Usage

      defmodule MyApp.PuzzleSolver do
        use Jido.AI.ToTAgent,
          name: "puzzle_solver",
          description: "Solves complex puzzles using tree exploration",
          branching_factor: 4,
          max_depth: 5,
          traversal_strategy: :best_first
      end

  ## Options

  - `:name` (required) - Agent name
  - `:description` - Agent description (default: "ToT agent \#{name}")
  - `:model` - Model identifier (default: "anthropic:claude-haiku-4-5")
  - `:branching_factor` - Number of thoughts to generate at each node (default: 3)
  - `:max_depth` - Maximum depth of the tree (default: 3)
  - `:traversal_strategy` - `:bfs`, `:dfs`, or `:best_first` (default: `:best_first`)
  - `:generation_prompt` - Custom prompt for thought generation
  - `:evaluation_prompt` - Custom prompt for thought evaluation
  - `:skills` - Additional skills to attach to the agent (TaskSupervisorSkill is auto-included)

  ## Generated Functions

  - `explore/2,3` - Async: sends prompt, returns `{:ok, %Request{}}` for later awaiting
  - `await/1,2` - Awaits a specific request's completion
  - `explore_sync/2,3` - Sync convenience: sends prompt and waits for result
  - `on_before_cmd/2` - Captures request in state before processing
  - `on_after_cmd/3` - Updates request result when done

  ## Request Tracking

  Each `explore/2` call returns a `Request` struct that can be awaited:

      {:ok, request} = MyAgent.explore(pid, "Solve the 8-puzzle")
      {:ok, result} = MyAgent.await(request, timeout: 30_000)

  Or use the synchronous convenience wrapper:

      {:ok, result} = MyAgent.explore_sync(pid, "Solve the 8-puzzle")

  ## State Fields

  The agent state includes:

  - `:model` - The LLM model being used
  - `:requests` - Map of request_id => request state (for concurrent tracking)
  - `:last_request_id` - ID of the most recent request
  - `:last_prompt` - The most recent prompt (backward compat)
  - `:last_result` - The final result from the last completed exploration (backward compat)
  - `:completed` - Boolean indicating if the last exploration is complete (backward compat)

  ## Task Supervisor

  Each agent instance gets its own Task.Supervisor automatically started via the
  `Jido.AI.Plugins.TaskSupervisor`. This supervisor is used for:
  - LLM streaming operations
  - Other async operations within the agent's lifecycle

  ## Example

      {:ok, pid} = Jido.AgentServer.start(agent: MyApp.PuzzleSolver)

      # Async pattern (preferred for concurrent requests)
      {:ok, request} = MyApp.PuzzleSolver.explore(pid, "Solve the 8-puzzle: [2,8,3,1,6,4,7,_,5]")
      {:ok, result} = MyApp.PuzzleSolver.await(request)

      # Sync pattern (convenience for simple cases)
      {:ok, result} = MyApp.PuzzleSolver.explore_sync(pid, "Solve the 8-puzzle: [2,8,3,1,6,4,7,_,5]")

  ## Traversal Strategies

  - `:bfs` - Breadth-first search: explores all nodes at current depth before going deeper
  - `:dfs` - Depth-first search: explores deeply before backtracking
  - `:best_first` - Explores highest-scored nodes first (default)
  """

  @default_model "anthropic:claude-haiku-4-5"
  @default_branching_factor 3
  @default_max_depth 3
  @default_traversal_strategy :best_first

  defmacro __using__(opts) do
    name = Keyword.fetch!(opts, :name)
    description = Keyword.get(opts, :description, "ToT agent #{name}")
    model = Keyword.get(opts, :model, @default_model)
    branching_factor = Keyword.get(opts, :branching_factor, @default_branching_factor)
    max_depth = Keyword.get(opts, :max_depth, @default_max_depth)
    traversal_strategy = Keyword.get(opts, :traversal_strategy, @default_traversal_strategy)
    generation_prompt = Keyword.get(opts, :generation_prompt)
    evaluation_prompt = Keyword.get(opts, :evaluation_prompt)
    plugins = Keyword.get(opts, :plugins, [])

    ai_plugins = [Jido.AI.Plugins.TaskSupervisor]

    strategy_opts =
      [
        model: model,
        branching_factor: branching_factor,
        max_depth: max_depth,
        traversal_strategy: traversal_strategy
      ]
      |> then(fn o ->
        if generation_prompt, do: Keyword.put(o, :generation_prompt, generation_prompt), else: o
      end)
      |> then(fn o ->
        if evaluation_prompt, do: Keyword.put(o, :evaluation_prompt, evaluation_prompt), else: o
      end)

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
          last_prompt: Zoi.string() |> Zoi.default(""),
          last_result: Zoi.string() |> Zoi.default(""),
          completed: Zoi.boolean() |> Zoi.default(false)
        })
      end

    quote location: :keep do
      use Jido.Agent,
        name: unquote(name),
        description: unquote(description),
        plugins: unquote(ai_plugins) ++ unquote(plugins),
        strategy: {Jido.AI.Strategies.TreeOfThoughts, unquote(Macro.escape(strategy_opts))},
        schema: unquote(base_schema_ast)

      unquote(Jido.AI.Agent.compatibility_overrides_ast())

      alias Jido.AI.Request

      @doc """
      Start a Tree-of-Thoughts exploration asynchronously.

      Returns `{:ok, %Request{}}` immediately. Use `await/2` to wait for the result.

      ## Examples

          {:ok, request} = MyAgent.explore(pid, "Solve the 8-puzzle")
          {:ok, result} = MyAgent.await(request)

      """
      @spec explore(pid() | atom() | {:via, module(), term()}, String.t(), keyword()) ::
              {:ok, Request.Handle.t()} | {:error, term()}
      def explore(pid, prompt, opts \\ []) when is_binary(prompt) do
        Request.create_and_send(
          pid,
          prompt,
          Keyword.merge(opts,
            signal_type: "ai.tot.query",
            source: "/ai/tot/agent"
          )
        )
      end

      @doc """
      Await the result of a specific request.

      ## Options

      - `:timeout` - How long to wait in milliseconds (default: 30_000)

      ## Examples

          {:ok, request} = MyAgent.explore(pid, "Solve the 8-puzzle")
          {:ok, result} = MyAgent.await(request, timeout: 10_000)

      """
      @spec await(Request.Handle.t(), keyword()) :: {:ok, any()} | {:error, term()}
      def await(request, opts \\ []) do
        Request.await(request, opts)
      end

      @doc """
      Start exploration and wait for the result synchronously.

      Convenience wrapper that combines `explore/3` and `await/2`.

      ## Options

      - `:timeout` - How long to wait in milliseconds (default: 30_000)

      ## Examples

          {:ok, result} = MyAgent.explore_sync(pid, "Solve the 8-puzzle", timeout: 10_000)

      """
      @spec explore_sync(pid() | atom() | {:via, module(), term()}, String.t(), keyword()) ::
              {:ok, any()} | {:error, term()}
      def explore_sync(pid, prompt, opts \\ []) when is_binary(prompt) do
        Request.send_and_await(
          pid,
          prompt,
          Keyword.merge(opts,
            signal_type: "ai.tot.query",
            source: "/ai/tot/agent"
          )
        )
      end

      @impl true
      def on_before_cmd(agent, {:tot_start, %{prompt: prompt} = params} = action) do
        # Ensure we have a request_id for tracking
        {request_id, params} = Request.ensure_request_id(params)
        action = {:tot_start, params}

        # Use RequestTracking to manage state (with prompt aliased as query)
        agent = Request.start_request(agent, request_id, prompt)
        # Also set last_prompt for ToT-specific backward compat
        agent = put_in(agent.state[:last_prompt], prompt)

        {:ok, agent, action}
      end

      @impl true
      def on_before_cmd(
            agent,
            {:tot_request_error, %{request_id: request_id, reason: reason, message: message}} = action
          ) do
        agent = Request.fail_request(agent, request_id, {:rejected, reason, message})
        {:ok, agent, action}
      end

      @impl true
      def on_before_cmd(agent, action), do: {:ok, agent, action}

      @impl true
      def on_after_cmd(agent, {:tot_start, %{request_id: request_id}}, directives) do
        snap = strategy_snapshot(agent)

        agent =
          if snap.done? do
            agent = Request.complete_request(agent, request_id, snap.result)
            # Also set last_result for ToT-specific backward compat
            put_in(agent.state[:last_result], snap.result || "")
          else
            agent
          end

        {:ok, agent, directives}
      end

      @impl true
      def on_after_cmd(agent, {:tot_request_error, _params}, directives) do
        {:ok, agent, directives}
      end

      @impl true
      def on_after_cmd(agent, _action, directives) do
        # Fallback for actions without request_id (backward compat)
        snap = strategy_snapshot(agent)

        agent =
          if snap.done? do
            %{
              agent
              | state:
                  Map.merge(agent.state, %{
                    last_result: snap.result || "",
                    completed: true
                  })
            }
          else
            agent
          end

        {:ok, agent, directives}
      end

      defoverridable on_before_cmd: 2, on_after_cmd: 3, explore: 3, await: 2, explore_sync: 3
    end
  end
end
