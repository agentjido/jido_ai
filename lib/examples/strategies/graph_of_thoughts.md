# Graph Of Thoughts Strategy Example

```elixir
defmodule MyApp.Synthesizer do
  use Jido.AI.GoTAgent,
    name: "synthesizer",
    model: :capable,
    max_nodes: 20,
    max_depth: 5,
    aggregation_strategy: :synthesis
end

{:ok, req} = MyApp.Synthesizer.explore(pid, "Synthesize release risks across multiple teams")
{:ok, result} = MyApp.Synthesizer.await(req)
```
