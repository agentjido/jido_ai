# TRM Strategy Example

```elixir
defmodule MyApp.RevisionAgent do
  use Jido.AI.TRMAgent,
    name: "revision_agent",
    model: :reasoning,
    max_supervision_steps: 5,
    act_threshold: 0.9
end

{:ok, req} = MyApp.RevisionAgent.reason(pid, "Improve this plan until it is implementation-ready")
{:ok, result} = MyApp.RevisionAgent.await(req)
```
