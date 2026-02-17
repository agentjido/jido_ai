# credo:disable-for-this-file Credo.Check.Refactor.LongQuoteBlocks

defmodule Jido.AI.TRMAgent do
  @moduledoc """
  Base macro for TRM (Tiny-Recursive-Model) agents.

  Wraps `use Jido.Agent` with `Jido.AI.Strategies.TRM` wired in,
  plus standard state fields and helper functions.

  ## Usage

      defmodule MyApp.ReasoningAgent do
        use Jido.AI.TRMAgent,
          name: "reasoning_agent",
          description: "Agent that improves answers through recursive reasoning",
          max_supervision_steps: 10,
          act_threshold: 0.95
      end

  ## Options

  - `:name` (required) - Agent name
  - `:description` - Agent description (default: "TRM agent \#{name}")
  - `:model` - Model identifier (default: "anthropic:claude-haiku-4-5")
  - `:max_supervision_steps` - Maximum supervision iterations before termination (default: 5)
  - `:act_threshold` - Confidence threshold for early stopping (default: 0.9)
  - `:skills` - Additional skills to attach to the agent (TaskSupervisorSkill is auto-included)

  ## Generated Functions

  - `reason/2,3` - Async: sends prompt, returns `{:ok, %Request{}}` for later awaiting
  - `await/1,2` - Awaits a specific request's completion
  - `reason_sync/2,3` - Sync convenience: sends prompt and waits for result
  - `strategy_opts/0` - Returns the strategy options (for CLI access)
  - `on_before_cmd/2` - Captures request in state before processing
  - `on_after_cmd/3` - Updates request result when done

  ## Request Tracking

  Each `reason/2` call returns a `Request` struct that can be awaited:

      {:ok, request} = MyAgent.reason(pid, "What is the best approach to solve X?")
      {:ok, result} = MyAgent.await(request, timeout: 30_000)

  Or use the synchronous convenience wrapper:

      {:ok, result} = MyAgent.reason_sync(pid, "What is the best approach to solve X?")

  ## State Fields

  The agent state includes:

  - `:model` - The LLM model being used
  - `:requests` - Map of request_id => request state (for concurrent tracking)
  - `:last_request_id` - ID of the most recent request
  - `:last_prompt` - The most recent prompt (backward compat)
  - `:last_result` - The final result from the last completed reasoning (backward compat)
  - `:completed` - Boolean indicating if the last reasoning is complete (backward compat)

  ## Task Supervisor

  Each agent instance gets its own Task.Supervisor automatically started via the
  `Jido.AI.Plugins.TaskSupervisor`. This supervisor is used for:
  - LLM streaming operations
  - Other async operations within the agent's lifecycle

  ## Example

      {:ok, pid} = Jido.AgentServer.start(agent: MyApp.ReasoningAgent)

      # Async pattern (preferred for concurrent requests)
      {:ok, request} = MyApp.ReasoningAgent.reason(pid, "What is the best approach to solve X?")
      {:ok, result} = MyApp.ReasoningAgent.await(request)

      # Sync pattern (convenience for simple cases)
      {:ok, result} = MyApp.ReasoningAgent.reason_sync(pid, "What is the best approach to solve X?")

  ## TRM Workflow

  TRM uses recursive reasoning to iteratively improve answers:
  1. **Reasoning**: Generate insights about the current answer
  2. **Supervision**: Evaluate the answer and provide feedback with a score
  3. **Improvement**: Apply feedback to generate a better answer
  4. Repeat until confidence threshold is met or max steps reached
  """

  @default_model "anthropic:claude-haiku-4-5"
  @default_max_supervision_steps 5
  @default_act_threshold 0.9

  defmacro __using__(opts) do
    name = Keyword.fetch!(opts, :name)
    description = Keyword.get(opts, :description, "TRM agent #{name}")
    model = Keyword.get(opts, :model, @default_model)
    max_supervision_steps = Keyword.get(opts, :max_supervision_steps, @default_max_supervision_steps)
    act_threshold = Keyword.get(opts, :act_threshold, @default_act_threshold)
    plugins = Keyword.get(opts, :plugins, [])

    ai_plugins = [Jido.AI.Plugins.TaskSupervisor]

    strategy_opts = [
      model: model,
      max_supervision_steps: max_supervision_steps,
      act_threshold: act_threshold
    ]

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
        strategy: {Jido.AI.Strategies.TRM, unquote(Macro.escape(strategy_opts))},
        schema: unquote(base_schema_ast)

      unquote(Jido.AI.Agent.compatibility_overrides_ast())

      alias Jido.AI.Request

      @doc """
      Returns the strategy options for this agent.

      Used by CLI adapters to introspect configuration.
      """
      def strategy_opts do
        unquote(Macro.escape(strategy_opts))
      end

      @doc """
      Start TRM recursive reasoning asynchronously.

      Returns `{:ok, %Request{}}` immediately. Use `await/2` to wait for the result.

      ## Examples

          {:ok, request} = MyAgent.reason(pid, "What is the best approach to solve X?")
          {:ok, result} = MyAgent.await(request)

      """
      @spec reason(pid() | atom() | {:via, module(), term()}, String.t(), keyword()) ::
              {:ok, Request.Handle.t()} | {:error, term()}
      def reason(pid, prompt, opts \\ []) when is_binary(prompt) do
        Request.create_and_send(
          pid,
          prompt,
          Keyword.merge(opts,
            signal_type: "ai.trm.query",
            source: "/ai/trm/agent"
          )
        )
      end

      @doc """
      Await the result of a specific request.

      ## Options

      - `:timeout` - How long to wait in milliseconds (default: 30_000)

      ## Examples

          {:ok, request} = MyAgent.reason(pid, "What is the best approach?")
          {:ok, result} = MyAgent.await(request, timeout: 10_000)

      """
      @spec await(Request.Handle.t(), keyword()) :: {:ok, any()} | {:error, term()}
      def await(request, opts \\ []) do
        Request.await(request, opts)
      end

      @doc """
      Start TRM reasoning and wait for the result synchronously.

      Convenience wrapper that combines `reason/3` and `await/2`.

      ## Options

      - `:timeout` - How long to wait in milliseconds (default: 30_000)

      ## Examples

          {:ok, result} = MyAgent.reason_sync(pid, "What is the best approach?", timeout: 10_000)

      """
      @spec reason_sync(pid() | atom() | {:via, module(), term()}, String.t(), keyword()) ::
              {:ok, any()} | {:error, term()}
      def reason_sync(pid, prompt, opts \\ []) when is_binary(prompt) do
        Request.send_and_await(
          pid,
          prompt,
          Keyword.merge(opts,
            signal_type: "ai.trm.query",
            source: "/ai/trm/agent"
          )
        )
      end

      @impl true
      def on_before_cmd(agent, {:trm_start, %{prompt: prompt} = params} = action) do
        # Ensure we have a request_id for tracking
        {request_id, params} = Request.ensure_request_id(params)
        action = {:trm_start, params}

        # Use RequestTracking to manage state (with prompt aliased as query)
        agent = Request.start_request(agent, request_id, prompt)
        # Also set last_prompt for TRM-specific backward compat
        agent = put_in(agent.state[:last_prompt], prompt)

        {:ok, agent, action}
      end

      @impl true
      def on_before_cmd(
            agent,
            {:trm_request_error, %{request_id: request_id, reason: reason, message: message}} = action
          ) do
        agent = Request.fail_request(agent, request_id, {:rejected, reason, message})
        {:ok, agent, action}
      end

      @impl true
      def on_before_cmd(agent, action), do: {:ok, agent, action}

      @impl true
      def on_after_cmd(agent, {:trm_start, %{request_id: request_id}}, directives) do
        snap = strategy_snapshot(agent)

        agent =
          if snap.done? do
            agent = Request.complete_request(agent, request_id, snap.result)
            # Also set last_result for TRM-specific backward compat
            put_in(agent.state[:last_result], snap.result || "")
          else
            agent
          end

        {:ok, agent, directives}
      end

      @impl true
      def on_after_cmd(agent, {:trm_request_error, _params}, directives) do
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

      defoverridable on_before_cmd: 2, on_after_cmd: 3, reason: 3, await: 2, reason_sync: 3
    end
  end
end
