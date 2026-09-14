# Reasoning Method Recipes

Jido AI uses one Agent authoring form for every reasoning method. Select the
method inside the `ai` profile. Each definition is inert until a request enters
the Agent runtime.

## Complete ReAct Agent

```elixir
defmodule MyApp.Multiply do
  use Jido.Action,
    name: "multiply",
    schema: Zoi.object(%{a: Zoi.integer(), b: Zoi.integer()})

  def run(%{a: a, b: b}, _context), do: {:ok, %{product: a * b}}
end

defmodule MyApp.Assistant do
  use Jido.AI.Agent, name: "assistant"

  agent do
    schema Zoi.object(%{answer: Zoi.any() |> Zoi.default(nil)})

    ai :assistant do
      instructions("Give a short and accurate answer.")

      models do
        model(:answer, :fast)
      end

      reasoning :react do
        model(:answer)
      end

      tools do
        action(MyApp.Multiply, as: :multiply)
      end

      requests do
        mode(:session)
        streaming(true)
        steering(true)
      end

      result(nil, into: :answer)
    end
  end

  routes do
    route("ai.ask", ai(:assistant))
  end
end
```

All Agent modules use `ask/3`, `ask_sync/3`, `ask_stream/3`, `await/2`,
`cancel/2`, and `steer/3`. There are no method-specific Agent macros or request
function names.

## Linear Methods

Use one of these reasoning blocks in the Agent above:

```elixir
reasoning :chain_of_draft do
  model(:answer)
end

reasoning :chain_of_thought do
  model(:answer)
end
```

Chain-of-Draft gives concise intermediate work. Chain-of-Thought gives a more
explicit linear decomposition. These methods do not execute tools or accept
steering.

## Algorithm of Thoughts

```elixir
reasoning :algorithm_of_thoughts do
  model(:answer)
  options(profile: :standard, search_style: :dfs, require_explicit_answer: true)
end
```

This is a one-pass algorithmic exploration method. It does not execute tools or
accept steering.

## Tree of Thoughts

```elixir
reasoning :tree_of_thoughts do
  model(:answer)
  options(branching_factor: 3, max_depth: 4, top_k: 3, max_nodes: 100)
end
```

Tree of Thoughts performs bounded branching search. It can use declared tools.
Use `Jido.AI.Reasoning.TreeOfThoughts.Result` to inspect its structured result.

## Graph of Thoughts

```elixir
reasoning :graph_of_thoughts do
  model(:answer)
  options(max_nodes: 20, max_depth: 5, aggregation_strategy: :synthesis)
end
```

Graph of Thoughts combines several candidate paths. It does not execute tools
or accept steering.

## TRM

```elixir
reasoning :trm do
  model(:answer)
  options(max_supervision_steps: 5, act_threshold: 0.9)
end
```

TRM applies recursive improvement. It does not execute tools or accept
steering.

## Adaptive Selection

```elixir
reasoning :adaptive do
  model(:answer)
  options(available_strategies: [:cod, :cot, :react, :aot, :tot, :got, :trm])
end
```

Adaptive selection chooses from the declared list for each request. Use
`strategy_override` when the caller must select one available method.

## Shared Controls

Use the same control block with every method:

```elixir
controls do
  max_iterations(8)
  max_model_calls(12)
  max_tool_calls(16)
  timeout(60_000)
end
```

These limits are independent. A request-specific `max_iterations` value does
not change `max_model_calls`.

See the checked examples under `examples/09_reasoning` for complete runtime
cases.
