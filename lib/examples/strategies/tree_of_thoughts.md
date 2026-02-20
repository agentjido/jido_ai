# Tree Of Thoughts Strategy Example

```elixir
defmodule MyApp.Explorer do
  use Jido.AI.ToTAgent,
    name: "explorer",
    model: :capable,
    max_depth: 3,
    beam_width: 4
end

{:ok, req} = MyApp.Explorer.explore(pid, "Compare 3 architecture options for a chat app")
{:ok, result} = MyApp.Explorer.await(req)
```
