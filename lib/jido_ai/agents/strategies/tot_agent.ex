# credo:disable-for-this-file Credo.Check.Refactor.LongQuoteBlocks

defmodule Jido.AI.ToTAgent do
  @moduledoc """
  Base macro for Tree-of-Thoughts-powered agents.

  Wraps `use Jido.Agent` with `Jido.AI.Reasoning.TreeOfThoughts.Strategy` wired in,
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
  - `:model` - Model alias or direct model spec (default: :fast, resolved via Jido.AI.resolve_model/1)
  - `:branching_factor`, `:max_depth`, `:traversal_strategy` - Core tree exploration knobs
  - `:top_k`, `:min_depth`, `:max_nodes`, `:max_duration_ms`, `:beam_width` - Search budget and shaping knobs
  - `:early_success_threshold`, `:convergence_window`, `:min_score_improvement`, `:max_parse_retries` - Deterministic stopping/parser controls
  - `:tools`, `:tool_context`, `:tool_timeout_ms`, `:tool_max_retries`, `:tool_retry_backoff_ms`, `:max_tool_round_trips` - Tool orchestration controls
  - `:generation_prompt` - Custom prompt for thought generation
  - `:evaluation_prompt` - Custom prompt for thought evaluation
  - `:skills` - Additional skills to attach to the agent (TaskSupervisorSkill is auto-included)

  ## Generated Functions

  - `explore/2,3` - Async: sends prompt, returns `{:ok, %Request{}}` for later awaiting
  - `await/1,2` - Awaits a specific request's completion
  - `explore_sync/2,3` - Sync convenience: sends prompt and waits for result
  - `on_before_cmd/2` - Captures request in state before processing
  - `on_after_cmd/3` - Updates request result when done
  - `best_answer/1`, `top_candidates/2`, `result_summary/1` - Structured result helpers

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

  ## Structured Result Contract

  `explore_sync/3` (and awaited async requests) resolve to a structured map:

  - `best` - best-ranked candidate
  - `candidates` - ranked candidate list
  - `termination` - reason/status/depth/node-count/duration metadata
  - `tree` - search topology metadata
  - `usage` - LLM usage metadata
  - `diagnostics` - parser/tool-round/convergence diagnostics

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

  @default_model :fast
  @default_branching_factor 3
  @default_max_depth 3
  @default_traversal_strategy :best_first
  @default_top_k 3
  @default_min_depth 2
  @default_max_nodes 100
  @default_early_success_threshold 1.0
  @default_convergence_window 2
  @default_min_score_improvement 0.02
  @default_max_parse_retries 1
  @default_max_tool_round_trips 3

  defmacro __using__(opts) do
    name = Keyword.fetch!(opts, :name)
    description = Keyword.get(opts, :description, "ToT agent #{name}")
    model = Keyword.get(opts, :model, @default_model)
    branching_factor = Keyword.get(opts, :branching_factor, @default_branching_factor)
    max_depth = Keyword.get(opts, :max_depth, @default_max_depth)
    traversal_strategy = Keyword.get(opts, :traversal_strategy, @default_traversal_strategy)
    generation_prompt = Keyword.get(opts, :generation_prompt)
    evaluation_prompt = Keyword.get(opts, :evaluation_prompt)
    top_k = Keyword.get(opts, :top_k, @default_top_k)
    min_depth = Keyword.get(opts, :min_depth, @default_min_depth)
    max_nodes = Keyword.get(opts, :max_nodes, @default_max_nodes)
    max_duration_ms = Keyword.get(opts, :max_duration_ms)
    beam_width = Keyword.get(opts, :beam_width)
    early_success_threshold = Keyword.get(opts, :early_success_threshold, @default_early_success_threshold)
    convergence_window = Keyword.get(opts, :convergence_window, @default_convergence_window)
    min_score_improvement = Keyword.get(opts, :min_score_improvement, @default_min_score_improvement)
    max_parse_retries = Keyword.get(opts, :max_parse_retries, @default_max_parse_retries)
    tools = Keyword.get(opts, :tools, [])
    tool_context = Keyword.get(opts, :tool_context, %{})
    tool_timeout_ms = Keyword.get(opts, :tool_timeout_ms, 15_000)
    tool_max_retries = Keyword.get(opts, :tool_max_retries, 1)
    tool_retry_backoff_ms = Keyword.get(opts, :tool_retry_backoff_ms, 200)
    max_tool_round_trips = Keyword.get(opts, :max_tool_round_trips, @default_max_tool_round_trips)
    plugins = Keyword.get(opts, :plugins, [])

    ai_plugins = Jido.AI.PluginStack.default_plugins(opts)

    strategy_opts =
      [
        model: model,
        branching_factor: branching_factor,
        max_depth: max_depth,
        traversal_strategy: traversal_strategy,
        top_k: top_k,
        min_depth: min_depth,
        max_nodes: max_nodes,
        max_duration_ms: max_duration_ms,
        beam_width: beam_width,
        early_success_threshold: early_success_threshold,
        convergence_window: convergence_window,
        min_score_improvement: min_score_improvement,
        max_parse_retries: max_parse_retries,
        tools: tools,
        tool_context: tool_context,
        tool_timeout_ms: tool_timeout_ms,
        tool_max_retries: tool_max_retries,
        tool_retry_backoff_ms: tool_retry_backoff_ms,
        max_tool_round_trips: max_tool_round_trips
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
          model: Zoi.any() |> Zoi.default(unquote(model)),
          # Request tracking for concurrent request isolation
          requests: Zoi.map() |> Zoi.default(%{}),
          last_request_id: Zoi.string() |> Zoi.optional(),
          # Backward compatibility fields (convenience pointers to most recent)
          last_prompt: Zoi.string() |> Zoi.default(""),
          last_result: Zoi.any() |> Zoi.default(nil),
          completed: Zoi.boolean() |> Zoi.default(false)
        })
      end

    quote location: :keep do
      use Jido.Agent,
        name: unquote(name),
        description: unquote(description),
        plugins: unquote(ai_plugins) ++ unquote(plugins),
        strategy: {Jido.AI.Reasoning.TreeOfThoughts.Strategy, unquote(Macro.escape(strategy_opts))},
        schema: unquote(base_schema_ast)

      unquote(Jido.AI.Agent.compatibility_overrides_ast())

      alias Jido.AI.Request
      alias Jido.AI.Reasoning.TreeOfThoughts.Result

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

      @doc """
      Returns the best answer string from a structured ToT result.
      """
      @spec best_answer(map() | nil) :: String.t() | nil
      def best_answer(result), do: Result.best_answer(result)

      @doc """
      Returns the top ranked candidates from a structured ToT result.
      """
      @spec top_candidates(map() | nil, pos_integer()) :: [map()]
      def top_candidates(result, limit \\ 3), do: Result.top_candidates(result, limit)

      @doc """
      Returns a compact summary of a structured ToT result.
      """
      @spec result_summary(map() | nil) :: map()
      def result_summary(%{} = result) do
        %{
          best_answer: best_answer(result),
          top_candidates: top_candidates(result, 3),
          termination: Map.get(result, :termination, %{}),
          tree: Map.get(result, :tree, %{})
        }
      end

      def result_summary(_), do: %{best_answer: nil, top_candidates: [], termination: %{}, tree: %{}}

      @impl true
      def on_before_cmd(agent, {:tot_start, %{prompt: prompt} = params} = action) do
        # Ensure we have a request_id for tracking
        {request_id, params} = Request.ensure_request_id(params)
        action = {:tot_start, params}

        # Use RequestTracking to manage state (with prompt aliased as query)
        agent = Request.start_request(agent, request_id, prompt)
        # Also set last_prompt for ToT-specific backward compat
        agent =
          agent
          |> put_in([Access.key(:state), Access.key(:last_prompt)], prompt)
          |> put_in([Access.key(:state), Access.key(:last_result)], nil)
          |> put_in([Access.key(:state), Access.key(:completed)], false)

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
          agent
          |> maybe_finalize_request(request_id, snap)
          |> maybe_put_last_result(snap)

        {:ok, agent, directives}
      end

      @impl true
      def on_after_cmd(agent, {:tot_request_error, _params}, directives) do
        {:ok, agent, directives}
      end

      @impl true
      def on_after_cmd(agent, action, directives) do
        # Fallback for actions without request_id (backward compat)
        snap = strategy_snapshot(agent)
        request_id = request_id_from_action(action, agent.state[:last_request_id])

        agent =
          agent
          |> maybe_finalize_request(request_id, snap)
          |> maybe_mark_completed(snap)

        {:ok, agent, directives}
      end

      defp maybe_finalize_request(agent, request_id, snap) do
        if request_pending?(agent, request_id) and snap.done? do
          case snap.status do
            :success ->
              Request.complete_request(agent, request_id, snap.result)

            :failure ->
              Request.fail_request(agent, request_id, failure_reason(snap))

            _ ->
              agent
          end
        else
          agent
        end
      end

      defp request_pending?(agent, request_id) when is_binary(request_id) do
        case Request.get_request(agent, request_id) do
          %{status: :pending} -> true
          _ -> false
        end
      end

      defp request_pending?(_agent, _request_id), do: false

      defp maybe_put_last_result(agent, snap) do
        if snap.done? do
          agent
          |> put_in([Access.key(:state), Access.key(:last_result)], snap.result)
          |> put_in([Access.key(:state), Access.key(:completed)], true)
        else
          agent
        end
      end

      defp maybe_mark_completed(agent, snap) do
        if snap.done? do
          %{
            agent
            | state:
                Map.merge(agent.state, %{
                  last_result: snap.result,
                  completed: true
                })
          }
        else
          agent
        end
      end

      defp request_id_from_action({_, params}, fallback) when is_map(params) do
        params[:request_id] ||
          get_in(params, [:event, :request_id]) ||
          fallback
      end

      defp request_id_from_action(_action, fallback), do: fallback

      defp failure_reason(snap) do
        details = Map.get(snap, :details, %{})

        case details[:termination_reason] do
          :cancelled -> {:cancelled, details[:cancel_reason] || :cancelled}
          nil -> {:failed, :unknown, snap.result}
          reason -> {:failed, reason, snap.result}
        end
      end

      defoverridable on_before_cmd: 2, on_after_cmd: 3, explore: 3, await: 2, explore_sync: 3
    end
  end
end
