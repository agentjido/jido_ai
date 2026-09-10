# Model Alias And ReqLLM Quickstart

Use ReqLLM for a direct model call. Use `Jido.AI.Models` only when your
application needs stable names such as `:fast` or `:capable`.

## Prerequisites

- Elixir `~> 1.18`
- `jido_ai` installed
- At least one provider key configured for ReqLLM

## 1. Configure Aliases

```elixir
# config/config.exs
config :jido_ai,
  model_aliases: %{
    fast: "provider:fast-model",
    capable: "provider:capable-model"
  }

config :req_llm,
  anthropic_api_key: System.get_env("ANTHROPIC_API_KEY"),
  openai_api_key: System.get_env("OPENAI_API_KEY")
```

The alias table can contain any model input accepted by ReqLLM. It can contain
a model string, tuple, inline model map, or `%LLMDB.Model{}` value.

## 2. Generate Text

```elixir
model = Jido.AI.Models.resolve(:fast)

{:ok, response} =
  ReqLLM.generate_text(
    model,
    "Summarize OTP in one sentence.",
    temperature: 0.3,
    max_tokens: 1_024,
    receive_timeout: 30_000
  )

text = ReqLLM.Response.text(response)
```

ReqLLM owns the request options and response contract. Jido AI does not add a
second defaults system or response wrapper.

## 3. Generate Structured Data

```elixir
schema = Zoi.object(%{
  title: Zoi.string(),
  priority: Zoi.enum([:low, :medium, :high])
})

model = Jido.AI.Models.resolve(:capable)

{:ok, response} =
  ReqLLM.generate_object(
    model,
    "Extract the title and priority from this incident.",
    schema
  )

result = ReqLLM.Response.object(response)
```

## 4. Stream Text

```elixir
model = Jido.AI.Models.resolve(:fast)

case ReqLLM.stream_text(model, "Write a short release note.") do
  {:ok, stream} -> ReqLLM.StreamResponse.text(stream)
  {:error, reason} -> {:error, reason}
end
```

The returned stream is a native ReqLLM stream.

## 5. Use A Direct Model Input

Aliases are optional:

```elixir
ReqLLM.generate_text(
  "anthropic:claude-sonnet-4-5",
  "Review this design."
)
```

`Jido.AI.Models.resolve/1` also passes a valid direct ReqLLM model input through
without changing it.

## Common Errors

An unknown atom is an unknown application alias:

```elixir
** (ArgumentError) Unknown model alias: :my_model
```

Add it under `config :jido_ai, model_aliases: ...`, or pass a direct ReqLLM
model input. Provider authentication and request failures use the normal ReqLLM
error contract.

## When To Use An Agent

Use direct ReqLLM calls for one model request. Use `Jido.AI.Agent` when you need
named AI profiles, tool loops, request tracking, Sessions, or reasoning policy.

## Next

- [Getting Started](getting_started.md)
- [Tool Calling With Actions](tool_calling_with_actions.md)
- [Configuration Reference](../developer/configuration_reference.md)
