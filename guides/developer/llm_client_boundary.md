# LLM Client Boundary

You need provider abstraction and deterministic testing without leaking provider details into strategy or action code.

After this guide, you can inject custom clients via context or app config.

## Boundary Module

`Jido.AI.LLMClient` defines callbacks:

- `generate_text/3`
- `stream_text/3`
- `process_stream/2`

Default implementation: `Jido.AI.LLMClient.ReqLLM`.

Resolution order:
1. `:llm_client` in call context
2. `:llm_client` application env
3. default ReqLLM implementation

## Test Client Injection

```elixir
defmodule MyApp.FakeLLMClient do
  @behaviour Jido.AI.LLMClient

  @impl true
  def generate_text(_model, _messages, _opts), do: {:ok, %{message: %{content: "ok"}}}

  @impl true
  def stream_text(_model, _messages, _opts), do: {:ok, :fake_stream}

  @impl true
  def process_stream(_stream, _opts), do: {:ok, %{message: %{content: "stream ok"}}}
end

ctx = %{llm_client: MyApp.FakeLLMClient}
{:ok, resp} = Jido.AI.LLMClient.generate_text(ctx, "anthropic:claude-haiku-4-5", [%{role: :user, content: "hi"}], [])
```

## Failure Mode: Context Client Ignored

Symptom:
- tests still hit real provider

Fix:
- pass a map/keyword context with `:llm_client`
- verify no wrapper replaces context before boundary call

## Defaults You Should Know

- app env key: `config :jido_ai, :llm_client, Module`
- all boundary functions accept `context` as first arg in public wrappers

## When To Use / Not Use

Use this boundary when:
- writing testable strategy/action logic
- integrating alternative providers or mocks

Do not use this boundary when:
- writing direct provider experiments outside package architecture

## Next

- [Strategy Internals](strategy_internals.md)
- [Streaming Workflows](../user/streaming_workflows.md)
- [Configuration Reference](configuration_reference.md)
