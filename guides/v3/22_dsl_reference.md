# AI Agent DSL reference

Use core Jido sections with one top-level `ai` section:

```elixir
defmodule MyApp.Agent do
  use Jido.AI.Agent, name: "my_agent"

  state do
    schema Zoi.object(%{session: Jido.Session.schema()})
  end

  ai do
    model :fast
    instructions "Answer briefly."
    reasoning MyApp.ReasoningFlow

    tools do
      action MyApp.Search, as: :search, timeout: 5_000
      flow MyApp.Research, as: :research, timeout: 10_000
    end

    controls do
      timeout 30_000
      max_iterations 4
      max_model_calls 4
      max_tool_calls 6
      input MyApp.Authorize
      output MyApp.ValidateOutput
    end
  end

  routes do
    signal_source "/my_app/agent"

    route "my_app.ask", MyApp.Turn, as: :ask do
      state from: output(:state)
      reply "my_app.answered", from: output(:reply)
    end
  end
end
```

## AI fields

| Form | Purpose |
| --- | --- |
| `model` | Model alias or provider model name |
| `instructions` | Static system instructions |
| `reasoning` | One Jido Flow module or inline `reasoning do` Flow |
| `tools` | Declared Jido Actions and Flows |
| `controls` | Total time and call limits, one input control, one output control |

The default reasoning Flow is `Jido.AI.Flow.ReAct`.

Input and output control slots accept one Action each. A control can be a
module Action or an inline Action. Controls cannot return effects.

## Generated helpers

`use Jido.AI.Agent` adds:

- `generate/2`
- `preflight/2`
- `reason/2`
- `run/2`
- `stream/2`

## Request options

Jido AI owns these options:

- `:context`
- `:conversation` for the older clean ReqLLM Context form
- `:projection`
- `:visible_tools`
- `:request_id`
- `:run_id`
- `:jido_context`

Other allowed options go to ReqLLM. Raw `:tools` is reserved and rejected.
Structured direct requests can use ReqLLM `:output`. Routed structured replies
use `reply: {Agent, input_type}`. Jido AI derives the model output schema from
the route handler output schema at the route reply path.

Use Map Agent definitions for portable authoring. Module Actions, Flows,
controls, and reasoning targets must resolve through the trusted Jido authoring
Registry when a definition is encoded or decoded.
