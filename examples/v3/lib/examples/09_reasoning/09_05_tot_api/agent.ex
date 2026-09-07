defmodule JidoAI.Examples.ToTAPI.Public do
  use Jido.AI.ToTAgent,
    name: "public_tree",
    model: :example,
    max_depth: 1,
    branching_factor: 2,
    tool_context: %{origin_label: "authoring"},
    tools: [JidoAI.Examples.ToolCallbacks.Work]

  @impl Jido.AI.ToolInterceptor
  def before_tool_call(call, context) do
    send(context.observer, {:tot_public_context, call.id, context})
    JidoAI.Examples.ToolCallbacks.Hooks.before_tool_call(call, context)
  end

  @impl Jido.AI.ToolInterceptor
  defdelegate after_tool_call(call, result, context), to: JidoAI.Examples.ToolCallbacks.Hooks
end

defmodule JidoAI.Examples.ToTAPI.Default do
  use Jido.AI.ToTAgent, name: "default_tree", model: :example
end

defmodule JidoAI.Examples.ToTAPI.Timed do
  use Jido.AI.ToTAgent,
    name: "timed_tree",
    model: :example,
    max_duration_ms: 100
end

defmodule JidoAI.Examples.ToTAPI.TimeoutOverride do
  use Jido.AI.ToTAgent,
    name: "tree_timeout_override",
    model: :example,
    max_duration_ms: 100,
    llm_timeout_ms: 250
end

defmodule JidoAI.Examples.ToTAPI.Custom do
  use Jido.AI.ToTAgent,
    name: "custom_tree",
    description: "Custom search",
    model: :example,
    max_depth: 1,
    branching_factor: 1,
    traversal_strategy: :bfs,
    top_k: 1,
    min_depth: 1,
    max_nodes: 20,
    generation_prompt: "Generate one approach",
    evaluation_prompt: "Score the approach",
    max_tokens: 73,
    temperature: 0.3,
    llm_opts: [max_tokens: 99, temperature: 0.4],
    streaming: false,
    effect_policy: %{allow: [Jido.AI.Effects.State]},
    strategy_effect_policy: %{mode: :allow_all}
end

defmodule JidoAI.Examples.ToTAPI.Aliases do
  use Jido.Agent, name: "tree_aliases", extensions: [Jido.AI.DSL]

  agent do
    schema Zoi.object(%{
             reply: Zoi.any() |> Zoi.default(nil),
             aliases: Zoi.map() |> Zoi.default(%{}),
             count: Zoi.integer() |> Zoi.default(0)
           })

    ai :assistant do
      tool_interceptor(JidoAI.Examples.ToolCallbacks.Hooks)
      effect_policy(%{allow: [Jido.AI.Effects.State]})

      models do
        model(:answer, JidoAI.Examples.MockLLM.model())
      end

      reasoning :tree_of_thoughts do
        model(:answer)
        options(max_depth: 1, branching_factor: 2)
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
      end

      requests do
        mode(:session)
        streaming(true)
      end

      result(nil, into: :reply)
    end
  end

  routes do
    route "ai.tot.query", ai(:assistant)
  end
end

defmodule JidoAI.Examples.ToTAPI.Deep do
  use Jido.AI.ToTAgent,
    name: "deep_tree",
    model: :example,
    max_depth: 2,
    branching_factor: 1,
    convergence_window: 1,
    tools: [JidoAI.Examples.ToolCallbacks.Work]
end
