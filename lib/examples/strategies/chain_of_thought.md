# Chain Of Thought Strategy Example

```elixir
defmodule MyApp.Reasoner do
  use Jido.AI.CoTAgent,
    name: "reasoner",
    model: :reasoning,
    system_prompt: "Think step by step and show concise reasoning."
end

{:ok, req} = MyApp.Reasoner.think(pid, "What is 15% of 340?")
{:ok, answer} = MyApp.Reasoner.await(req)
```
