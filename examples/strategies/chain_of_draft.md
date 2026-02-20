# Chain Of Draft Strategy Example

```elixir
defmodule MyApp.DraftReasoner do
  use Jido.AI.CoDAgent,
    name: "draft_reasoner",
    model: :reasoning
end

{:ok, req} = MyApp.DraftReasoner.draft(pid, "Jason had 20 lollipops. He gave Denny some and now has 12. How many did he give?")
{:ok, answer} = MyApp.DraftReasoner.await(req)
```
