# credo:disable-for-this-file Credo.Check.Refactor.LongQuoteBlocks

defmodule Jido.AI.GoTAgent do
  @moduledoc """
  Base macro for Graph-of-Thoughts-powered agents.

  Wraps `use Jido.Agent` with `Jido.AI.Strategies.GraphOfThoughts` wired in,
  plus standard state fields and helper functions.

  ## Usage

      defmodule MyApp.ResearchSynthesizer do
        use Jido.AI.GoTAgent,
          name: "research_synthesizer",
          description: "Synthesizes research from multiple perspectives",
          max_nodes: 30,
          max_depth: 6,
          aggregation_strategy: :synthesis
      end

  ## Options

  - `:name` (required) - Agent name
  - `:description` - Agent description (default: "GoT agent \#{name}")
  - `:model` - Model identifier (default: "anthropic:claude-haiku-4-5")
  - `:max_nodes` - Maximum number of nodes in the graph (default: 20)
  - `:max_depth` - Maximum depth of the graph (default: 5)
  - `:aggregation_strategy` - `:voting`, `:weighted`, or `:synthesis` (default: `:synthesis`)
  - `:generation_prompt` - Custom prompt for thought generation
  - `:connection_prompt` - Custom prompt for finding connections
  - `:aggregation_prompt` - Custom prompt for aggregation
  - `:skills` - Additional skills to attach to the agent (TaskSupervisorSkill is auto-included)

  ## Generated Functions

  - `explore/2,3` - Async: sends prompt, returns `{:ok, %Request{}}` for later awaiting
  - `await/1,2` - Awaits a specific request's completion
  - `explore_sync/2,3` - Sync convenience: sends prompt and waits for result
  - `strategy_opts/0` - Returns the strategy options for CLI access
  - `on_before_cmd/2` - Captures request in state before processing
  - `on_after_cmd/3` - Updates request result when done

  ## Request Tracking

  Each `explore/2` call returns a `Request` struct that can be awaited:

      {:ok, request} = MyAgent.explore(pid, "Analyze the impact of AI on healthcare")
      {:ok, result} = MyAgent.await(request, timeout: 30_000)

  Or use the synchronous convenience wrapper:

      {:ok, result} = MyAgent.explore_sync(pid, "Analyze the impact of AI on healthcare")

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

      {:ok, pid} = Jido.AgentServer.start(agent: MyApp.ResearchSynthesizer)

      # Async pattern (preferred for concurrent requests)
      {:ok, request} = MyApp.ResearchSynthesizer.explore(pid, "Analyze the impact of AI on healthcare")
      {:ok, result} = MyApp.ResearchSynthesizer.await(request)

      # Sync pattern (convenience for simple cases)
      {:ok, result} = MyApp.ResearchSynthesizer.explore_sync(pid, "Analyze the impact of AI on healthcare")

  ## Aggregation Strategies

  - `:voting` - Selects the most common conclusion among thoughts
  - `:weighted` - Weights thoughts by their scores when aggregating
  - `:synthesis` - Synthesizes all thoughts into a coherent conclusion (default)
  """

  @default_model "anthropic:claude-haiku-4-5"
  @default_max_nodes 20
  @default_max_depth 5
  @default_aggregation_strategy :synthesis

  defmacro __using__(opts) do
    name = Keyword.fetch!(opts, :name)
    description = Keyword.get(opts, :description, "GoT agent #{name}")
    model = Keyword.get(opts, :model, @default_model)
    max_nodes = Keyword.get(opts, :max_nodes, @default_max_nodes)
    max_depth = Keyword.get(opts, :max_depth, @default_max_depth)
    aggregation_strategy = Keyword.get(opts, :aggregation_strategy, @default_aggregation_strategy)
    generation_prompt = Keyword.get(opts, :generation_prompt)
    connection_prompt = Keyword.get(opts, :connection_prompt)
    aggregation_prompt = Keyword.get(opts, :aggregation_prompt)
    plugins = Keyword.get(opts, :plugins, [])

    ai_plugins = [Jido.AI.Plugins.TaskSupervisor]

    strategy_opts =
      [
        model: model,
        max_nodes: max_nodes,
        max_depth: max_depth,
        aggregation_strategy: aggregation_strategy
      ]
      |> then(fn o ->
        if generation_prompt, do: Keyword.put(o, :generation_prompt, generation_prompt), else: o
      end)
      |> then(fn o ->
        if connection_prompt, do: Keyword.put(o, :connection_prompt, connection_prompt), else: o
      end)
      |> then(fn o ->
        if aggregation_prompt, do: Keyword.put(o, :aggregation_prompt, aggregation_prompt), else: o
      end)

    base_schema_ast =
      quote do
        Zoi.object(%{
          __strategy__: Zoi.map() |> Zoi.default(%{}),
          model: Zoi.string() |> Zoi.default(unquote(model)),
          requests: Zoi.map() |> Zoi.default(%{}),
          last_request_id: Zoi.string() |> Zoi.optional(),
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
        strategy: {Jido.AI.Strategies.GraphOfThoughts, unquote(Macro.escape(strategy_opts))},
        schema: unquote(base_schema_ast)

      unquote(Jido.AI.Agent.compatibility_overrides_ast())

      alias Jido.AI.Request

      @doc """
      Returns the strategy options configured for this agent.
      Used by the CLI adapter to inspect configuration.
      """
      def strategy_opts, do: unquote(Macro.escape(strategy_opts))

      @doc """
      Start a Graph-of-Thoughts exploration asynchronously.

      Returns `{:ok, %Request{}}` immediately. Use `await/2` to wait for the result.

      ## Examples

          {:ok, request} = MyAgent.explore(pid, "Analyze the impact of AI on healthcare")
          {:ok, result} = MyAgent.await(request)

      """
      @spec explore(pid() | atom() | {:via, module(), term()}, String.t(), keyword()) ::
              {:ok, Request.Handle.t()} | {:error, term()}
      def explore(pid, prompt, opts \\ []) when is_binary(prompt) do
        Request.create_and_send(
          pid,
          prompt,
          Keyword.merge(opts,
            signal_type: "ai.got.query",
            source: "/ai/got/agent"
          )
        )
      end

      @doc """
      Await the result of a specific request.

      ## Options

      - `:timeout` - How long to wait in milliseconds (default: 30_000)

      ## Examples

          {:ok, request} = MyAgent.explore(pid, "Analyze the impact of AI on healthcare")
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

          {:ok, result} = MyAgent.explore_sync(pid, "Analyze the impact of AI on healthcare", timeout: 10_000)

      """
      @spec explore_sync(pid() | atom() | {:via, module(), term()}, String.t(), keyword()) ::
              {:ok, any()} | {:error, term()}
      def explore_sync(pid, prompt, opts \\ []) when is_binary(prompt) do
        Request.send_and_await(
          pid,
          prompt,
          Keyword.merge(opts,
            signal_type: "ai.got.query",
            source: "/ai/got/agent"
          )
        )
      end

      @impl true
      def on_before_cmd(agent, {:got_start, %{prompt: prompt} = params} = action) do
        {request_id, params} = Request.ensure_request_id(params)
        action = {:got_start, params}

        agent = Request.start_request(agent, request_id, prompt)
        agent = put_in(agent.state[:last_prompt], prompt)

        {:ok, agent, action}
      end

      @impl true
      def on_before_cmd(
            agent,
            {:got_request_error, %{request_id: request_id, reason: reason, message: message}} = action
          ) do
        agent = Request.fail_request(agent, request_id, {:rejected, reason, message})
        {:ok, agent, action}
      end

      @impl true
      def on_before_cmd(agent, action), do: {:ok, agent, action}

      @impl true
      def on_after_cmd(agent, {:got_start, %{request_id: request_id}}, directives) do
        snap = strategy_snapshot(agent)

        agent =
          if snap.done? do
            agent = Request.complete_request(agent, request_id, snap.result)
            put_in(agent.state[:last_result], snap.result || "")
          else
            agent
          end

        {:ok, agent, directives}
      end

      @impl true
      def on_after_cmd(agent, {:got_request_error, _params}, directives) do
        {:ok, agent, directives}
      end

      @impl true
      def on_after_cmd(agent, _action, directives) do
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
