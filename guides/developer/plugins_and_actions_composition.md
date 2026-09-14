# Plugins and Actions

Jido AI uses normal Jido Plugins and Actions. AI authoring does not create a
separate plugin stack or Strategy contract.

## Ownership

- A `Jido.Action` is one executable operation.
- A `Jido.Plugin` adds reusable state and command handling to an Agent.
- A `Jido.AI.Profile` defines inert AI policy.
- `Jido.AI.Session` and `Jido.AI.Runtime` own live AI request execution.

Declare ordinary plugins in the Agent block:

```elixir
defmodule MyApp.Assistant do
  use Jido.AI.Agent, name: "assistant"

  agent do
    schema Zoi.object(%{answer: Zoi.any() |> Zoi.default(nil)})

    plugin Jido.AI.Plugins.ModelRouting,
      config: [routes: %{"ai.ask" => :capable}]

    ai :assistant do
      models do
        model(:answer, :fast)
      end

      reasoning :react do
        model(:answer)
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

## Capability Plugins

The package includes Chat, Planning, Retrieval, Quota, Policy, ModelRouting,
and callable reasoning plugins. Each plugin uses the core Jido declaration and
route model. The checked examples under `examples/16_capabilities` show the
supported composition form.

## Direct Actions

Use `Jido.Exec.run/3` when an Agent session is not required. Public Actions
cover model calls, tool calling, planning, retrieval, quota operations, skill
loading, and callable reasoning.

```elixir
Jido.Exec.run(
  Jido.AI.Actions.LLM.Chat,
  %{prompt: "Summarize this incident."},
  context: %{model: Jido.AI.Models.resolve(:fast)}
)
```

Do not add a method-specific Agent macro, private Directive executor, or plugin
stack helper. Extend the Spark DSL for authoring data, or add a normal Plugin or
Action for an optional capability.
