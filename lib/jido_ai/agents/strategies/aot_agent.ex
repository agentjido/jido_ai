# credo:disable-for-this-file Credo.Check.Refactor.LongQuoteBlocks

defmodule Jido.AI.AoTAgent do
  @moduledoc """
  Base macro for Algorithm-of-Thoughts-powered agents.

  Wraps `use Jido.Agent` with `Jido.AI.Reasoning.AlgorithmOfThoughts.Strategy`
  and provides request-oriented helper APIs.
  """

  @default_model :fast
  @default_profile :standard
  @default_search_style :dfs
  @default_temperature 0.0
  @default_max_tokens 2048

  defmacro __using__(opts) do
    name = Keyword.fetch!(opts, :name)
    description = Keyword.get(opts, :description, "AoT agent #{name}")
    model = Keyword.get(opts, :model, @default_model)
    profile = Keyword.get(opts, :profile, @default_profile)
    search_style = Keyword.get(opts, :search_style, @default_search_style)
    temperature = Keyword.get(opts, :temperature, @default_temperature)
    max_tokens = Keyword.get(opts, :max_tokens, @default_max_tokens)
    examples = Keyword.get(opts, :examples, [])
    require_explicit_answer = Keyword.get(opts, :require_explicit_answer, true)
    plugins = Keyword.get(opts, :plugins, [])

    ai_plugins = Jido.AI.PluginStack.default_plugins(opts)

    strategy_opts = [
      model: model,
      profile: profile,
      search_style: search_style,
      temperature: temperature,
      max_tokens: max_tokens,
      examples: examples,
      require_explicit_answer: require_explicit_answer
    ]

    base_schema_ast =
      quote do
        Zoi.object(%{
          __strategy__: Zoi.map() |> Zoi.default(%{}),
          model: Zoi.any() |> Zoi.default(unquote(model)),
          requests: Zoi.map() |> Zoi.default(%{}),
          last_request_id: Zoi.string() |> Zoi.optional(),
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
        strategy: {Jido.AI.Reasoning.AlgorithmOfThoughts.Strategy, unquote(Macro.escape(strategy_opts))},
        schema: unquote(base_schema_ast)

      unquote(Jido.AI.Agent.compatibility_overrides_ast())

      alias Jido.AI.Request

      @doc "Returns configured strategy options."
      def strategy_opts, do: unquote(Macro.escape(strategy_opts))

      @doc "Start AoT exploration asynchronously."
      @spec explore(pid() | atom() | {:via, module(), term()}, String.t(), keyword()) ::
              {:ok, Request.Handle.t()} | {:error, term()}
      def explore(pid, prompt, opts \\ []) when is_binary(prompt) do
        Request.create_and_send(
          pid,
          prompt,
          Keyword.merge(opts,
            signal_type: "ai.aot.query",
            source: "/ai/aot/agent"
          )
        )
      end

      @doc "Await the result of a specific request."
      @spec await(Request.Handle.t(), keyword()) :: {:ok, any()} | {:error, term()}
      def await(request, opts \\ []) do
        Request.await(request, opts)
      end

      @doc "Start AoT exploration and wait synchronously."
      @spec explore_sync(pid() | atom() | {:via, module(), term()}, String.t(), keyword()) ::
              {:ok, any()} | {:error, term()}
      def explore_sync(pid, prompt, opts \\ []) when is_binary(prompt) do
        Request.send_and_await(
          pid,
          prompt,
          Keyword.merge(opts,
            signal_type: "ai.aot.query",
            source: "/ai/aot/agent"
          )
        )
      end

      @impl true
      def on_before_cmd(agent, {:aot_start, %{prompt: prompt} = params} = action) do
        {request_id, params} = Request.ensure_request_id(params)
        action = {:aot_start, params}

        agent = Request.start_request(agent, request_id, prompt)
        agent = put_in(agent.state[:last_prompt], prompt)

        {:ok, agent, action}
      end

      @impl true
      def on_before_cmd(
            agent,
            {:aot_request_error, %{request_id: request_id, reason: reason, message: message}} = action
          ) do
        agent = Request.fail_request(agent, request_id, {:rejected, reason, message})
        {:ok, agent, action}
      end

      @impl true
      def on_before_cmd(agent, action), do: {:ok, agent, action}

      @impl true
      def on_after_cmd(agent, {:aot_start, %{request_id: request_id}}, directives) do
        snap = strategy_snapshot(agent)

        agent =
          agent
          |> maybe_finalize_request(request_id, snap)
          |> maybe_put_last_result(snap)

        {:ok, agent, directives}
      end

      @impl true
      def on_after_cmd(agent, {:aot_request_error, _params}, directives) do
        {:ok, agent, directives}
      end

      @impl true
      def on_after_cmd(agent, action, directives) do
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
          put_in(agent, [Access.key(:state), Access.key(:last_result)], snap.result)
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

      @doc "Extracts the answer string from AoT result payload."
      @spec answer(map() | nil) :: String.t() | nil
      def answer(%{answer: answer}) when is_binary(answer), do: answer
      def answer(_), do: nil

      defoverridable on_before_cmd: 2, on_after_cmd: 3, explore: 3, await: 2, explore_sync: 3
    end
  end
end
