# ReAct Strategy Example

```elixir
defmodule MyApp.WeatherAgent do
  use Jido.AI.ReActAgent,
    name: "weather_agent",
    model: :capable,
    tools: [Jido.Tools.Weather],
    request_policy: :reject,
    tool_timeout_ms: 15_000,
    tool_max_retries: 1,
    tool_retry_backoff_ms: 200,
    observability: %{
      emit_telemetry?: true,
      emit_lifecycle_signals?: true,
      redact_tool_args?: true,
      emit_llm_deltas?: true
    }
end
```

Use async request handles:

```elixir
{:ok, req} = MyApp.WeatherAgent.ask(pid, "Will it rain in Seattle?")
{:ok, answer} = MyApp.WeatherAgent.await(req, timeout: 30_000)
```
