# Reasoning Method Selection

Choose a reasoning method inside a `Jido.AI.Agent` profile.

| Method | Use it for | Avoid it for | DSL value |
|---|---|---|---|
| Chain of Draft | Short linear reasoning | Branching exploration | `:chain_of_draft` |
| Chain of Thought | Clear linear decomposition | Tool orchestration | `:chain_of_thought` |
| ReAct | Tool calls and iterative reasoning | Static one-pass work | `:react` |
| Algorithm of Thoughts | One-pass algorithmic exploration | Multi-round search | `:algorithm_of_thoughts` |
| Tree of Thoughts | Bounded branching search | Low-latency questions | `:tree_of_thoughts` |
| Graph of Thoughts | Multi-path synthesis | Small deterministic work | `:graph_of_thoughts` |
| TRM | Iterative refinement | Fast one-pass answers | `:trm` |
| Adaptive | Mixed request shapes | Deterministic method selection | `:adaptive` |

Start with ReAct when tools are required. Start with Chain of Draft for short
linear reasoning. Use Tree or Graph methods only when a search structure gives
a clear benefit.

## Adaptive Example

```elixir
defmodule MyApp.SmartAgent do
  use Jido.AI.Agent, name: "smart_agent"

  agent do
    schema Zoi.object(%{answer: Zoi.any() |> Zoi.default(nil)})

    ai :assistant do
      models do
        model(:answer, :capable)
      end

      reasoning :adaptive do
        model(:answer)
        options(available_strategies: [:cod, :cot, :react, :tot, :got, :trm])
      end

      requests do
        mode(:session)
      end

      result(nil, into: :answer)
    end
  end

  routes do
    route("ai.ask", ai(:assistant))
  end
end
```

Adaptive selection has no `default_strategy` option. It selects from
`available_strategies`, or it uses an explicit `strategy_override`.

See [Reasoning Method Recipes](strategy_recipes.md) for complete authoring
forms.
