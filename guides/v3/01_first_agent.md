# Your first AI Agent

Define one Agent with one AI section:

```elixir
defmodule MyApp.AnswerAgent do
  use Jido.AI.Agent, name: "answer_agent"

  ai do
    model "openai:gpt-4o-mini"
    instructions "Answer in one short sentence."

    controls do
      timeout 10_000
      max_model_calls 1
    end
  end
end
```

Generate one output:

```elixir
{:ok, answer} = MyApp.AnswerAgent.generate("What is Jido AI?")
```

Inspect one prepared request without a model call:

```elixir
{:ok, request} = MyApp.AnswerAgent.preflight("What is Jido AI?")

request.model
Jido.AI.Request.messages(request)
request.controls
```

Read a completed result with usage and events:

```elixir
{:ok, result} = MyApp.AnswerAgent.reason("What is Jido AI?")

result.output
result.usage
result.events
```

Inspect the Flow that defines the Agent behavior:

```elixir
MyApp.AnswerAgent.graph()
#=> Jido.AI.Reasoning.ReAct
```

Use `graph MyApp.Flow` in the `ai` block to select another behavior graph.
The older `reasoning` declaration remains available as a compatibility alias.

These direct calls do not start an AgentServer and do not change Agent state.
Use a route with explicit `state` and `reply` projections when the application
must commit Session, Thread, or domain state.

Continue with [tools and ReAct](02_tools_and_react.md).
