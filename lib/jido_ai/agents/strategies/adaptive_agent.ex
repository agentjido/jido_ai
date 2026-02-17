# credo:disable-for-this-file Credo.Check.Refactor.LongQuoteBlocks

defmodule Jido.AI.AdaptiveAgent do
  @moduledoc """
  Base macro for Adaptive strategy-powered agents.

  Wraps `use Jido.Agent` with `Jido.AI.Strategies.Adaptive` wired in,
  plus standard state fields and helper functions.

  ## Usage

      defmodule MyApp.SmartAssistant do
        use Jido.AI.AdaptiveAgent,
          name: "smart_assistant",
          description: "Automatically selects the best reasoning approach",
          default_strategy: :react,
          available_strategies: [:cot, :react, :tot, :got, :trm]
      end

  ## Options

  - `:name` (required) - Agent name
  - `:description` - Agent description (default: "Adaptive agent \#{name}")
  - `:model` - Model identifier (default: "anthropic:claude-haiku-4-5")
  - `:default_strategy` - Default strategy if analysis is inconclusive (default: `:react`)
  - `:available_strategies` - List of available strategies (default: `[:cot, :react, :tot, :got, :trm]`)
  - `:complexity_thresholds` - Map of thresholds for strategy selection
  - `:skills` - Additional skills to attach to the agent (TaskSupervisorSkill is auto-included)

  ## Generated Functions

  - `ask/2,3` - Async: sends query, returns `{:ok, %Request{}}` for later awaiting
  - `await/1,2` - Awaits a specific request's completion
  - `ask_sync/2,3` - Sync convenience: sends query and waits for result
  - `strategy_opts/0` - Returns the strategy options (for CLI access)
  - `on_before_cmd/2` - Captures request in state before processing
  - `on_after_cmd/3` - Updates request result when done

  ## Request Tracking

  Each `ask/2` call returns a `Request` struct that can be awaited:

      {:ok, request} = MyAgent.ask(pid, "Solve this puzzle: ...")
      {:ok, result} = MyAgent.await(request, timeout: 30_000)

  Or use the synchronous convenience wrapper:

      {:ok, result} = MyAgent.ask_sync(pid, "Solve this puzzle: ...")

  ## State Fields

  The agent state includes:

  - `:model` - The LLM model being used
  - `:requests` - Map of request_id => request state (for concurrent tracking)
  - `:last_request_id` - ID of the most recent request
  - `:last_prompt` - The most recent prompt (backward compat)
  - `:last_result` - The final result from the last completed reasoning (backward compat)
  - `:completed` - Boolean indicating if the last reasoning is complete (backward compat)
  - `:selected_strategy` - The strategy type selected for the current task

  ## Task Supervisor

  Each agent instance gets its own Task.Supervisor automatically started via the
  `Jido.AI.Plugins.TaskSupervisor`. This supervisor is used for:
  - LLM streaming operations
  - Other async operations within the agent's lifecycle

  ## Example

      {:ok, pid} = Jido.AgentServer.start(agent: MyApp.SmartAssistant)

      # Async pattern (preferred for concurrent requests)
      {:ok, request} = MyApp.SmartAssistant.ask(pid, "Solve this puzzle: ...")
      {:ok, result} = MyApp.SmartAssistant.await(request)

      # Sync pattern (convenience for simple cases)
      {:ok, result} = MyApp.SmartAssistant.ask_sync(pid, "Solve this puzzle: ...")

      # Check the selected strategy
      agent = Jido.AgentServer.get(pid)
      agent.state.selected_strategy # => :trm

  ## Strategy Selection

  The Adaptive strategy automatically selects the best approach based on task analysis:

  - **Iterative Reasoning** → TRM (puzzles, step-by-step, recursive)
  - **Synthesis** → Graph-of-Thoughts (combine, merge, perspectives)
  - **Tool use** → ReAct (search, calculate, execute)
  - **Exploration** → Tree-of-Thoughts (analyze, compare, alternatives)
  - **Simple tasks** → Chain-of-Thought (direct questions, factual queries)
  """

  @default_model "anthropic:claude-haiku-4-5"
  @default_strategy :react
  @default_available_strategies [:cot, :react, :tot, :got, :trm]

  defmacro __using__(opts) do
    name = Keyword.fetch!(opts, :name)
    description = Keyword.get(opts, :description, "Adaptive agent #{name}")
    model = Keyword.get(opts, :model, @default_model)
    default_strategy = Keyword.get(opts, :default_strategy, @default_strategy)
    available_strategies = Keyword.get(opts, :available_strategies, @default_available_strategies)
    complexity_thresholds = Keyword.get(opts, :complexity_thresholds)
    plugins = Keyword.get(opts, :plugins, [])

    ai_plugins = [Jido.AI.Plugins.TaskSupervisor]

    strategy_opts =
      [
        model: model,
        default_strategy: default_strategy,
        available_strategies: available_strategies
      ]
      |> then(fn o ->
        if complexity_thresholds,
          do: Keyword.put(o, :complexity_thresholds, complexity_thresholds),
          else: o
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
          completed: Zoi.boolean() |> Zoi.default(false),
          selected_strategy: Zoi.atom() |> Zoi.default(nil) |> Zoi.nullable()
        })
      end

    quote location: :keep do
      use Jido.Agent,
        name: unquote(name),
        description: unquote(description),
        plugins: unquote(ai_plugins) ++ unquote(plugins),
        strategy: {Jido.AI.Strategies.Adaptive, unquote(Macro.escape(strategy_opts))},
        schema: unquote(base_schema_ast)

      unquote(Jido.AI.Agent.compatibility_overrides_ast())

      alias Jido.AI.Request

      @doc """
      Returns the strategy options configured for this agent.
      """
      def strategy_opts do
        unquote(Macro.escape(strategy_opts))
      end

      @doc """
      Send an adaptive query to the agent asynchronously.

      Returns `{:ok, %Request{}}` immediately. Use `await/2` to wait for the result.

      ## Options

      - `:timeout` - Timeout for the underlying cast (default: no timeout)

      ## Examples

          {:ok, request} = MyAgent.ask(pid, "Solve this puzzle: ...")
          {:ok, result} = MyAgent.await(request)

      """
      @spec ask(pid() | atom() | {:via, module(), term()}, String.t(), keyword()) ::
              {:ok, Request.Handle.t()} | {:error, term()}
      def ask(pid, prompt, opts \\ []) when is_binary(prompt) do
        Request.create_and_send(
          pid,
          prompt,
          Keyword.merge(opts,
            signal_type: "ai.adaptive.query",
            source: "/ai/adaptive/agent"
          )
        )
      end

      @doc """
      Await the result of a specific request.

      ## Options

      - `:timeout` - How long to wait in milliseconds (default: 30_000)

      ## Examples

          {:ok, request} = MyAgent.ask(pid, "Solve this puzzle: ...")
          {:ok, result} = MyAgent.await(request, timeout: 10_000)

      """
      @spec await(Request.Handle.t(), keyword()) :: {:ok, any()} | {:error, term()}
      def await(request, opts \\ []) do
        Request.await(request, opts)
      end

      @doc """
      Send an adaptive query and wait for the result synchronously.

      Convenience wrapper that combines `ask/3` and `await/2`.

      ## Options

      - `:timeout` - How long to wait in milliseconds (default: 30_000)

      ## Examples

          {:ok, result} = MyAgent.ask_sync(pid, "Solve this puzzle: ...", timeout: 10_000)

      """
      @spec ask_sync(pid() | atom() | {:via, module(), term()}, String.t(), keyword()) ::
              {:ok, any()} | {:error, term()}
      def ask_sync(pid, prompt, opts \\ []) when is_binary(prompt) do
        Request.send_and_await(
          pid,
          prompt,
          Keyword.merge(opts,
            signal_type: "ai.adaptive.query",
            source: "/ai/adaptive/agent"
          )
        )
      end

      @impl true
      def on_before_cmd(agent, {:adaptive_start, %{prompt: prompt} = params} = _action) do
        # Ensure we have a request_id for tracking
        {request_id, params} = Request.ensure_request_id(params)
        action = {:adaptive_start, params}

        # Use RequestTracking to manage state
        agent = Request.start_request(agent, request_id, prompt)
        # Also set last_prompt for adaptive-specific backward compat
        agent = put_in(agent.state[:last_prompt], prompt)

        {:ok, agent, action}
      end

      @impl true
      def on_before_cmd(
            agent,
            {:adaptive_request_error, %{request_id: request_id, reason: reason, message: message}} = action
          ) do
        agent = Request.fail_request(agent, request_id, {:rejected, reason, message})
        {:ok, agent, action}
      end

      @impl true
      def on_before_cmd(agent, action), do: {:ok, agent, action}

      @impl true
      def on_after_cmd(agent, {:adaptive_start, %{request_id: request_id}}, directives) do
        snap = strategy_snapshot(agent)

        # Extract selected strategy from strategy state
        strategy_state = Map.get(agent.state, :__strategy__, %{})
        selected_strategy = Map.get(strategy_state, :strategy_type)

        agent =
          if snap.done? do
            agent = Request.complete_request(agent, request_id, snap.result)
            # Also set selected_strategy for adaptive-specific backward compat
            put_in(agent.state[:selected_strategy], selected_strategy)
          else
            put_in(agent.state[:selected_strategy], selected_strategy)
          end

        {:ok, agent, directives}
      end

      @impl true
      def on_after_cmd(agent, {:adaptive_request_error, _params}, directives) do
        {:ok, agent, directives}
      end

      @impl true
      def on_after_cmd(agent, _action, directives) do
        # Fallback for actions without request_id (backward compat)
        snap = strategy_snapshot(agent)

        # Extract selected strategy from strategy state
        strategy_state = Map.get(agent.state, :__strategy__, %{})
        selected_strategy = Map.get(strategy_state, :strategy_type)

        agent =
          if snap.done? do
            %{
              agent
              | state:
                  Map.merge(agent.state, %{
                    last_result: snap.result || "",
                    completed: true,
                    selected_strategy: selected_strategy
                  })
            }
          else
            %{
              agent
              | state: Map.put(agent.state, :selected_strategy, selected_strategy)
            }
          end

        {:ok, agent, directives}
      end

      defoverridable on_before_cmd: 2, on_after_cmd: 3, ask: 3, await: 2, ask_sync: 3
    end
  end
end
