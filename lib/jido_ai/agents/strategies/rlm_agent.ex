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
  - `:extra_tools` - Additional Jido.Action modules beyond RLM exploration tools
  - `:plugins` - Additional plugins (TaskSupervisorSkill is auto-included)

  ## Generated Functions

  - `explore/3` - Async: sends query + context, returns `{:ok, %Request.Handle{}}`
  - `await/2` - Awaits a specific request's completion
  - `explore_sync/3` - Sync convenience: sends query and waits for result
  - `cancel/2` - Cancel in-flight request

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
    name = Keyword.fetch!(opts, :name)
    description = Keyword.get(opts, :description, "RLM agent #{name}")
    model = Keyword.get(opts, :model, @default_model)
    recursive_model = Keyword.get(opts, :recursive_model, @default_recursive_model)
    max_iterations = Keyword.get(opts, :max_iterations, @default_max_iterations)
    plugins = Keyword.get(opts, :plugins, [])

    extra_tools_ast = Keyword.get(opts, :extra_tools, [])

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
      extra_tools: extra_tools
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

      defoverridable on_before_cmd: 2,
                     on_after_cmd: 3,
                     explore: 3,
                     await: 2,
                     explore_sync: 3,
                     cancel: 2
    end
  end
end
