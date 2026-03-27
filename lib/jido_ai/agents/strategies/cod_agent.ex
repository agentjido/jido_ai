# credo:disable-for-this-file Credo.Check.Refactor.LongQuoteBlocks

defmodule Jido.AI.CoDAgent do
  @moduledoc """
  Base macro for Chain-of-Draft-powered agents.

  Wraps `use Jido.Agent` with `Jido.AI.Reasoning.ChainOfDraft.Strategy` wired in,
  plus standard state fields and helper functions.
  """

  @default_model :fast

  defp system_prompt_line({_, meta, _}, default), do: Keyword.get(meta, :line, default)
  defp system_prompt_line(_, default), do: default

  defmacro __using__(opts) do
    name = Keyword.fetch!(opts, :name)
    description = Keyword.get(opts, :description, "CoD agent #{name}")

    model =
      opts
      |> Keyword.get(:model, @default_model)
      |> Jido.AI.Agent.expand_and_eval_literal_option(__CALLER__)

    default_system_prompt = Jido.AI.Reasoning.ChainOfDraft.default_system_prompt()

    system_prompt_raw =
      case Keyword.fetch(opts, :system_prompt) do
        :error -> default_system_prompt
        {:ok, value} -> value
      end

    system_prompt_line = system_prompt_line(system_prompt_raw, __CALLER__.line)

    system_prompt =
      case system_prompt_raw do
        {:@, _, [{_name, _, _}]} = attr_ast ->
          {:deferred, attr_ast}

        other ->
          expanded = Macro.expand(other, __CALLER__)

          if Macro.quoted_literal?(expanded) do
            {resolved, _binding} = Code.eval_quoted(expanded, [], __CALLER__)

            case Jido.AI.Agent.normalize_system_prompt_value(resolved, __CALLER__.file, system_prompt_line) do
              :absent -> {:resolved, default_system_prompt}
              {:resolved, value} -> {:resolved, value}
            end
          else
            raise CompileError,
              description:
                "system_prompt only supports binaries, nil, false, compile-time literal expressions, or bare module attributes",
              file: __CALLER__.file,
              line: system_prompt_line
          end
      end

    plugins = Keyword.get(opts, :plugins, [])

    ai_plugins = Jido.AI.PluginStack.default_plugins(opts)

    strategy_opts =
      [model: model]
      |> then(fn o ->
        case system_prompt do
          {:resolved, value} -> Keyword.put(o, :system_prompt, value)
          {:deferred, _attr_ast} -> o
        end
      end)

    strategy_opts_ast =
      case system_prompt do
        {:deferred, attr_ast} ->
          quote do
            case Jido.AI.Agent.normalize_system_prompt_value(
                   unquote(attr_ast),
                   __ENV__.file,
                   unquote(system_prompt_line)
                 ) do
              :absent ->
                Keyword.put(unquote(Macro.escape(strategy_opts)), :system_prompt, unquote(default_system_prompt))

              {:resolved, value} ->
                Keyword.put(unquote(Macro.escape(strategy_opts)), :system_prompt, value)
            end
          end

        _ ->
          Macro.escape(strategy_opts)
      end

    base_schema_ast =
      quote do
        Zoi.object(%{
          __strategy__: Zoi.map() |> Zoi.default(%{}),
          model: Zoi.any() |> Zoi.default(unquote(Macro.escape(model))),
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
        strategy: {Jido.AI.Reasoning.ChainOfDraft.Strategy, unquote(strategy_opts_ast)},
        schema: unquote(base_schema_ast)

      unquote(Jido.AI.Agent.compatibility_overrides_ast())

      alias Jido.AI.Request

      @doc """
      Returns the strategy options configured for this agent.
      """
      def strategy_opts do
        unquote(strategy_opts_ast)
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
          agent
          |> maybe_finalize_request(request_id, snap)
          |> maybe_put_last_result(snap)

        {:ok, agent, directives}
      end

      @impl true
      def on_after_cmd(agent, {:cod_request_error, _params}, directives) do
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
              Request.complete_request_from_snapshot(agent, request_id, snap)

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
          put_in(agent.state[:last_result], compat_result(snap.result))
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
                  last_result: compat_result(snap.result),
                  completed: true
                })
          }
        else
          agent
        end
      end

      defp compat_result(nil), do: ""
      defp compat_result(value) when is_binary(value), do: value
      defp compat_result(value), do: inspect(value)

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

      defoverridable on_before_cmd: 2, on_after_cmd: 3, draft: 3, await: 2, draft_sync: 3
    end
  end
end
