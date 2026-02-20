# Algorithm Of Thoughts Strategy Example

```elixir
defmodule MyApp.AlgorithmicReasoner do
  use Jido.AI.AoTAgent,
    name: "algorithmic_reasoner",
    model: :reasoning,
    profile: :standard,
    search_style: :dfs,
    require_explicit_answer: true
end

{:ok, req} = MyApp.AlgorithmicReasoner.explore(pid, "Compare options and provide a single final answer")
{:ok, result} = MyApp.AlgorithmicReasoner.await(req)
answer = result.answer
```
