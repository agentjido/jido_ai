# Add tools and ReAct

Declare Jido Actions and Flows as model tools:

```elixir
defmodule MyApp.ToolAgent do
  use Jido.AI.Agent, name: "tool_agent"

  ai do
    model "openai:gpt-4o-mini"
    instructions "Use a tool when it is useful."

    tools do
      action MyApp.Search, as: :search, timeout: 5_000
      flow MyApp.Research, as: :research, timeout: 10_000
    end

    controls do
      timeout 30_000
      max_iterations 3
      max_model_calls 4
      max_tool_calls 4
    end
  end
end
```

The default `Jido.AI.Flow.ReAct` Flow performs these steps:

1. Call the model with visible tool definitions.
2. Validate the complete tool-call batch.
3. Run valid Actions and Flows as child Flow components.
4. Append correlated tool results to the active model Context.
5. Continue until the model returns final output or a limit stops the request.

One request can reduce the visible set:

```elixir
{:ok, result} =
  MyApp.ToolAgent.reason("Search for the account",
    visible_tools: [:search]
  )
```

The request cannot add tools. A hidden or unknown call is rejected before any
tool executes.

Tool results are request evidence. They do not automatically update Agent
state. Use an explicit routed Action for a domain state change.

Continue with [results and state](03_results_and_state.md).
