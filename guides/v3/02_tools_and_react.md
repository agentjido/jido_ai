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

1. `CallModel` produces a portable `ModelOutcome`.
2. `InterpretOutcome` produces an `AgentDecision`.
3. `ExpandDecision` selects the completion Flow or the tool-round Flow.
4. `PlanTools` validates the complete tool-call batch and produces a
   `ToolPlan`.
5. `ExpandTools` adds only declared Actions and Flows as child graph nodes.
6. An observation node appends correlated tool results to the model Context.
7. The graph continues until it reaches completion or a limit.

The model supplies data. It cannot select an arbitrary module or execute a
tool directly.

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
