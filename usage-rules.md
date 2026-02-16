# Jido.AI Usage Rules

Jido.AI is an AI integration layer for Jido agents. Prefer action modules and strategy agents over ad-hoc facade calls.

## Core Usage

### Model Selection

```elixir
Jido.AI.resolve_model(:fast)
#=> "anthropic:claude-haiku-4-5"
```

### Text Generation via Actions

```elixir
{:ok, result} =
  Jido.Exec.run(Jido.AI.Actions.LLM.Chat, %{
    model: "anthropic:claude-haiku-4-5",
    prompt: "Explain recursion",
    temperature: 0.3
  })

result.text
```

### Structured Output via Actions

```elixir
schema = Zoi.object(%{name: Zoi.string(), age: Zoi.integer()})

{:ok, result} =
  Jido.Exec.run(Jido.AI.Actions.LLM.GenerateObject, %{
    model: "openai:gpt-4o-mini",
    prompt: "Generate a person object",
    schema: schema
  })
```

## Agent Pattern (`Jido.AI.Agent`)

```elixir
defmodule MyApp.Agent do
  use Jido.AI.Agent,
    name: "my_agent",
    tools: [Jido.Tools.Arithmetic.Add],
    model: :fast,
    request_policy: :reject,
    tool_timeout_ms: 15_000,
    tool_max_retries: 1,
    tool_retry_backoff_ms: 200
end

{:ok, pid} = Jido.AgentServer.start(agent: MyApp.Agent)
{:ok, request} = MyApp.Agent.ask(pid, "What is 2 + 2?")
{:ok, answer} = MyApp.Agent.await(request, timeout: 30_000)
```

## Error Handling

```elixir
case MyApp.Agent.ask_sync(pid, "Run a complex task", timeout: 10_000) do
  {:ok, result} -> {:ok, result}
  {:error, {:rejected, :busy, _msg}} -> {:error, :agent_busy}
  {:error, {:cancelled, reason}} -> {:error, {:cancelled, reason}}
  {:error, :timeout} -> {:error, :timeout}
  {:error, reason} -> {:error, reason}
end
```

## Observability

Attach telemetry to ReAct lifecycle/tool/LLM events. Start with:

- `[:jido, :ai, :react, :request, :start]`
- `[:jido, :ai, :react, :request, :complete]`
- `[:jido, :ai, :react, :request, :failed]`
- `[:jido, :ai, :react, :llm, :start]`
- `[:jido, :ai, :react, :llm, :complete]`
- `[:jido, :ai, :react, :tool, :start]`
- `[:jido, :ai, :react, :tool, :complete]`
- `[:jido, :ai, :react, :tool, :error]`
