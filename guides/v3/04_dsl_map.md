# How the AI DSL fits together

`use Jido.AI.Agent` keeps the core Jido Agent definition and adds AI profiles.
The outer `agent` block owns the state schema and Plugins. Each `ai` block
defines a named profile. The `routes` block connects a Signal to that profile.
The authoring compiler checks the definition before an Agent instance starts.

```elixir
use Jido.AI.Agent, name: "support_agent"

agent do
  schema Zoi.object(%{reply: Zoi.string() |> Zoi.default("")})

  ai :assistant do
    model "openai:gpt-4o-mini"
    instructions "Be concise."
    reasoning :react

    tools do
      action MyApp.Lookup, as: :lookup
    end

    controls do
      timeout 20_000
      max_model_calls 3
    end

    result into: :reply
  end
end

routes do
  route "support.ask", ai: :assistant do
    define :ask_case, args: [:query]
  end
end
```

Read this from the outside in. The state schema is the durable domain shape.
The profile describes one kind of AI work. `model` and `instructions` shape
the provider request. `reasoning` chooses how model and tool steps are
sequenced. `tools` exposes only declared operations. `controls` bounds work
and can add stage checks. `result` validates and maps the answer. The route
makes the profile reachable through Jido's Signal system.

`memory` and `observability` are optional blocks, not prerequisites for the
first answer. Memory selects retained Context; observability controls what
request evidence is kept. Add them when the application needs those contracts.
Do not put runtime PIDs, HTTP clients, or request handles in the Agent state.
They belong to live execution context.

The [DSL reference](22_dsl_reference.md) lists supported blocks and points to
their tests. Next, learn [models and profiles](05_models_profiles_instructions.md).
