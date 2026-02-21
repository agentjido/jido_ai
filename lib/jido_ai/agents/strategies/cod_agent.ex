# credo:disable-for-this-file Credo.Check.Refactor.LongQuoteBlocks

defmodule Jido.AI.CoDAgent do
  @moduledoc """
  Base macro for Chain-of-Draft-powered agents.

  Wraps `use Jido.Agent` with `Jido.AI.Reasoning.ChainOfDraft.Strategy` wired in,
  plus standard state fields and helper functions.
  """

  @default_model :fast

  defmacro __using__(opts) do
    name = Keyword.fetch!(opts, :name)
    description = Keyword.get(opts, :description, "CoD agent #{name}")
    model = Keyword.get(opts, :model, @default_model)
    system_prompt = Keyword.get(opts, :system_prompt, Jido.AI.Reasoning.ChainOfDraft.default_system_prompt())
    plugins = Keyword.get(opts, :plugins, [])

    ai_plugins = Jido.AI.PluginStack.default_plugins(opts)

    strategy_opts = [model: model, system_prompt: system_prompt]

    base_schema_ast =
      quote do
        Zoi.object(%{
          __strategy__: Zoi.map() |> Zoi.default(%{}),
          model: Zoi.any() |> Zoi.default(unquote(model)),
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
        strategy: {Jido.AI.Reasoning.ChainOfDraft.Strategy, unquote(Macro.escape(strategy_opts))},
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
      Start a Chain-of-Draft reasoning session asynchronously.
      """
      @spec draft(pid() | atom() | {:via, module(), term()}, String.t(), keyword()) ::
              {:ok, Request.Handle.t()} | {:error, term()}
      def draft(pid, prompt, opts \\ []) when is_binary(prompt) do
        Request.create_and_send(
          pid,
          prompt,
          Keyword.merge(opts,
            signal_type: "ai.cod.query",
            source: "/ai/cod/agent"
          )
        )
      end

      @doc """
      Await the result of a specific request.
      """
      @spec await(Request.Handle.t(), keyword()) :: {:ok, any()} | {:error, term()}
      def await(request, opts \\ []) do
        Request.await(request, opts)
      end

      @doc """
      Start reasoning and wait for the result synchronously.
      """
      @spec draft_sync(pid() | atom() | {:via, module(), term()}, String.t(), keyword()) ::
              {:ok, any()} | {:error, term()}
      def draft_sync(pid, prompt, opts \\ []) when is_binary(prompt) do
        Request.send_and_await(
          pid,
          prompt,
          Keyword.merge(opts,
            signal_type: "ai.cod.query",
            source: "/ai/cod/agent"
          )
        )
      end

      @impl true
      def on_before_cmd(agent, {:cod_start, %{prompt: prompt} = params} = action) do
        {request_id, params} = Request.ensure_request_id(params)
        action = {:cod_start, params}
        agent = Request.start_request(agent, request_id, prompt)
        agent = put_in(agent.state[:last_prompt], prompt)
        {:ok, agent, action}
      end

      @impl true
      def on_before_cmd(
            agent,
            {:cod_request_error, %{request_id: request_id, reason: reason, message: message}} = action
          ) do
        agent = Request.fail_request(agent, request_id, {:rejected, reason, message})
        {:ok, agent, action}
      end

      @impl true
      def on_before_cmd(agent, action), do: {:ok, agent, action}

      @impl true
      def on_after_cmd(agent, {:cod_start, %{request_id: request_id}}, directives) do
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
      def on_after_cmd(agent, {:cod_request_error, _params}, directives) do
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

      defoverridable on_before_cmd: 2, on_after_cmd: 3, draft: 3, await: 2, draft_sync: 3
    end
  end
end
