# Adaptive Strategy Example

```elixir
defmodule MyApp.AdaptiveAgent do
  use Jido.AI.AdaptiveAgent,
    name: "adaptive_agent",
    model: :capable,
    available_strategies: [:cod, :cot, :react, :tot, :got, :trm]
end

{:ok, req} = MyApp.AdaptiveAgent.solve(pid, "Plan and execute a release checklist")
{:ok, result} = MyApp.AdaptiveAgent.await(req)
```
