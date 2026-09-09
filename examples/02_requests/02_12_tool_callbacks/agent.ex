defmodule JidoAI.Examples.ToolCallbacks.ListItems do
  @moduledoc false
  use Jido.Action, name: "list_items", schema: Zoi.object(%{})
  def key, do: "warehouse/customer-47/product-2026-09-06/blue-widget"

  def run(_, context) do
    send(context.observer, {:listed, key()})
    {:ok, %{items: [%{key: key()}]}}
  end
end

defmodule JidoAI.Examples.ToolCallbacks.Consume do
  @moduledoc false
  use Jido.Action, name: "consume_item", schema: Zoi.object(%{key: Zoi.string() |> Zoi.min(30)})

  def run(%{key: key}, context) do
    send(context.observer, {:consumed, key})

    if key == JidoAI.Examples.ToolCallbacks.ListItems.key(),
      do: {:ok, %{used: key}},
      else: {:error, :wrong_key}
  end
end

defmodule JidoAI.Examples.ToolCallbacks.Work do
  @moduledoc false
  use Jido.Action, name: "callback_work", schema: Zoi.object(%{n: Zoi.integer()})

  def run(%{n: n}, context) do
    count =
      Elixir.Agent.get_and_update(
        context.counter,
        &{Map.get(&1, n, 0) + 1, Map.update(&1, n, 1, fn v -> v + 1 end)}
      )

    send(context.observer, {:tool_ran, n, count, self()})
    if context[:output_file], do: File.write!(context.output_file, "Tool #{n} ran")

    if context[:hold_n] == n or n in Map.get(context, :hold_ns, []),
      do:
        (receive do
           :release -> :ok
         end)

    if context[:fail_always] == true or (context[:retry] == true and count == 1),
      do: {:error, Jido.Action.Error.execution_error("Try once more", %{retry: true})},
      else: {:ok, %{n: n}}
  end
end

defmodule JidoAI.Examples.ToolCallbacks.WorkFlow do
  @moduledoc false
  use Jido.Flow, name: "callback_work_flow", schema: Zoi.object(%{n: Zoi.integer()})

  flow do
    step "work", action: JidoAI.Examples.ToolCallbacks.Work, params: input()
    output result("work")
  end
end

defmodule JidoAI.Examples.ToolCallbacks.Hooks do
  @moduledoc "Aliases are explicit candidate state; original Action keys stay unchanged."
  @behaviour Jido.AI.ToolInterceptor

  def before_tool_call(call, context) do
    send(context.observer, {:before_hook, call, context.agent_state})
    report_context(:before, context)
    hold(:before, context)

    case context[:before_mode] do
      :error -> {:error, :before_denied}
      :interrupt -> {:interrupt, :approval_needed}
      :invalid -> :invalid
      :raise -> raise "Before failed"
      :throw -> throw(:before_failed)
      :exit -> exit(:before_failed)
      :id -> {:ok, %{call | id: "forged"}}
      :name -> {:ok, %{call | name: "forged"}}
      :target -> {:ok, %{call | action_module: __MODULE__}}
      :invalid_args -> {:ok, %{call | arguments: %{"n" => "invalid"}}}
      _ -> prepare(call, context)
    end
  end

  defp prepare(%{name: "consume_item"} = call, context) do
    key = Map.get(context.agent_state.aliases, call.arguments["key"], call.arguments["key"])
    {:ok, %{call | arguments: %{"key" => key}}}
  end

  defp prepare(%{name: "callback_work"} = call, _context) do
    n = call.arguments["n"]
    {:ok, %{call | arguments: %{"n" => if(is_binary(n), do: String.to_integer(n), else: n)}}}
  end

  defp prepare(call, _), do: {:ok, call}

  def after_tool_call(call, result, context) do
    send(context.observer, {:after_hook, call, result, context.agent_state})
    report_context(:after, context)
    hold(:after, context)

    case if(context[:fail_after_id] == call.id, do: :error, else: context[:after_mode]) do
      :error -> {:error, :after_denied}
      :invalid -> {:ok, {:ok, :two_elements}}
      :raise -> raise "After failed"
      :throw -> throw(:after_failed)
      :exit -> exit(:after_failed)
      _ -> transform(call, result, context)
    end
  end

  defp transform(%{name: "list_items"}, {:ok, %{items: [%{key: key}]}, effects}, context) do
    next = %{context.agent_state | aliases: %{"item-1" => key}}
    {:ok, {:ok, %{items: [%{key: "item-1"}]}, effects ++ [Jido.AI.Effects.state(next)]}}
  end

  defp transform(%{name: "callback_work"}, {:ok, %{n: n}, effects}, context) do
    effects =
      if context[:add_effects],
        do:
          effects ++
            [
              Jido.AI.Effects.state(%{context.agent_state | count: n}),
              %JidoAI.Examples.ToolEffects.Record{receiver: context.observer, label: "callback"}
            ],
        else: effects

    {:ok, {:ok, %{n: n + 100}, effects}}
  end

  defp transform(_, result, _), do: {:ok, result}

  defp report_context(stage, context) do
    send(
      context.observer,
      {:hook_context, stage,
       Map.take(context, [:request_id, :run_id, :agent_id, :agent_module, :effect_policy, :state])}
    )
  end

  defp hold(stage, context) do
    if context[:hold_hook] == stage do
      send(context.observer, {:hook_waiting, stage, self()})

      receive do
        :release -> :ok
      end
    end
  end
end

defmodule JidoAI.Examples.ToolCallbacks.Transform do
  @moduledoc false
  @behaviour Jido.AI.Reasoning.ReAct.RequestTransformer
  def transform_request(_request, state, config, context) do
    send(context.observer, {:callback_view, state, config, context})
    {:ok, %{}}
  end
end

defmodule JidoAI.Examples.ToolCallbacks.Control do
  @moduledoc false
  @behaviour Jido.AI.Control
  def check(call, context) do
    send(context.observer, {:operation_checked, call})

    if context[:deny_n] != nil and context[:deny_n] == call.arguments[:n],
      do: {:error, :operation_denied},
      else: :ok
  end
end

defmodule JidoAI.Examples.ToolCallbacks.Agent do
  @moduledoc "A native Agent uses one explicit callback module in all source forms."
  use Jido.Agent, name: "tool_callback_example", extensions: [Jido.AI.DSL]

  agent do
    schema Zoi.object(%{
             reply: Zoi.string() |> Zoi.default(""),
             aliases: Zoi.map() |> Zoi.default(%{}),
             count: Zoi.integer() |> Zoi.default(0)
           })

    plugin JidoAI.Examples.ToolEffects.Observer

    ai :assistant do
      tool_interceptor(JidoAI.Examples.ToolCallbacks.Hooks)
      effect_policy(%{allow: [Jido.AI.Effects.State]})

      models do
        model(:answer, JidoAI.Examples.MockLLM.model())
      end

      reasoning :react do
        model(:answer)
        tool_concurrency(2)
        request_transformer(JidoAI.Examples.ToolCallbacks.Transform)
        effect_policy(%{mode: :allow_all})
      end

      controls do
        operation(JidoAI.Examples.ToolCallbacks.Control)
      end

      tools do
        action JidoAI.Examples.ToolCallbacks.ListItems,
          as: :list_items,
          forward_context: [:observer]

        action JidoAI.Examples.ToolCallbacks.Consume,
          as: :consume_item,
          forward_context: [:observer]

        action JidoAI.Examples.ToolCallbacks.Work,
          as: :callback_work,
          forward_context: [:observer, :counter, :retry, :output_file, :hold_n, :hold_ns]
      end

      requests do
        mode(:session)
      end

      result(nil, into: :reply)
    end
  end

  routes do
    route "ai.ask", ai(:assistant)
  end
end

defmodule JidoAI.Examples.ToolCallbacks.PublicAgent do
  @moduledoc false
  use Jido.AI.Agent,
    name: "public_callback_example",
    model: :example,
    tools: [JidoAI.Examples.ToolCallbacks.Work],
    streaming: false,
    tool_retry_backoff_ms: 0

  @impl Jido.AI.ToolInterceptor
  defdelegate before_tool_call(call, context), to: JidoAI.Examples.ToolCallbacks.Hooks
  @impl Jido.AI.ToolInterceptor
  defdelegate after_tool_call(call, result, context), to: JidoAI.Examples.ToolCallbacks.Hooks
end
