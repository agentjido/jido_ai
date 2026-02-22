# LLM Facade Quickstart

You want one-shot LLM generation without running a long-lived agent process.

After this guide, you can use `Jido.AI.generate_text/2`, `generate_object/3`, `stream_text/2`, and `ask/2` with model aliases and sane defaults.

## Prerequisites

- Elixir `~> 1.18`
- `jido_ai` dependency installed
- at least one provider key configured under `:req_llm`

## 1. Configure Aliases And LLM Defaults

```elixir
# config/config.exs
config :jido_ai,
  model_aliases: %{
    fast: "provider:fast-model",
    capable: "provider:capable-model",
    thinking: "provider:thinking-model"
  },
  llm_defaults: %{
    text: %{model: :fast, temperature: 0.2, max_tokens: 1024, timeout: 30_000},
    object: %{model: :thinking, temperature: 0.0, max_tokens: 1024, timeout: 30_000},
    stream: %{model: :fast, temperature: 0.2, max_tokens: 1024, timeout: 30_000}
  }

config :req_llm,
  anthropic_api_key: System.get_env("ANTHROPIC_API_KEY"),
  openai_api_key: System.get_env("OPENAI_API_KEY")
```

`Jido.AI.resolve_model/1` resolves aliases at runtime, so you can keep app code model-agnostic.

## 2. Quick Text Generation

```elixir
# Full response envelope from ReqLLM
{:ok, response} =
  Jido.AI.generate_text(
    "Summarize OTP in one sentence.",
    model: :fast,
    temperature: 0.3
  )

# Convenience text-only helper
{:ok, text} = Jido.AI.ask("Summarize OTP in one sentence.", model: :fast)
```

Use `generate_text/2` when you need full provider response metadata.  
Use `ask/2` when you only need normalized text.

## 3. Structured Output With `generate_object/3`

```elixir
schema = %{
  type: "object",
  properties: %{
    "title" => %{type: "string"},
    "priority" => %{type: "string", enum: ["low", "medium", "high"]}
  },
  required: ["title", "priority"]
}

{:ok, result} =
  Jido.AI.generate_object(
    "Extract title and priority from: Urgent production incident in checkout",
    schema,
    model: :thinking
  )
```

Use this path when downstream code expects stable structured fields instead of free-form text.

## 4. Streaming With `stream_text/2`

```elixir
case Jido.AI.stream_text("Write a short release note for version 2.0", model: :fast) do
  {:ok, stream_response} ->
    # Consume this with your ReqLLM streaming pipeline.
    stream_response

  {:error, reason} ->
    {:error, reason}
end
```

`stream_text/2` is a thin pass-through to ReqLLM streaming behavior.

## 5. Override Defaults Per Call

```elixir
# Uses llm_defaults(:text)
{:ok, _} = Jido.AI.generate_text("Default-path call")

# Override default model/timeout for one call
{:ok, _} =
  Jido.AI.generate_text(
    "High-importance call",
    model: :capable,
    timeout: 60_000,
    max_tokens: 2048
  )
```

`Jido.AI.llm_defaults/0` and `Jido.AI.llm_defaults/1` are useful for debugging effective runtime config.

## Failure Mode: Unknown Model Alias

Symptom:

```elixir
** (ArgumentError) Unknown model alias: :my_model
```

Fix:
- add alias under `config :jido_ai, model_aliases: ...`
- or pass a direct model string (`"provider:exact-model-id"`)

## Failure Mode: Provider Credential Missing

Symptom:
- provider authentication/request errors from ReqLLM

Fix:
- set provider key in `config :req_llm, ...`
- verify the selected model belongs to a configured provider

## Defaults You Should Know

- `llm_defaults(:text)` default model is `:fast`, `temperature: 0.2`, `max_tokens: 1024`, `timeout: 30_000`
- `llm_defaults(:object)` default model is `:thinking`, `temperature: 0.0`
- `llm_defaults(:stream)` default model is `:fast`
- built-in aliases include `:fast`, `:capable`, `:thinking`, `:reasoning`, `:planning`, `:image`, `:embedding`

## When To Use / Not Use

Use this facade when:
- you need one-shot generation from jobs, controllers, or scripts
- you do not need request-handle orchestration or tool loops

Do not use this facade when:
- you need multi-step tool-calling workflows (`Jido.AI.Agent`)
- you need strategy-level control (`Jido.AI.*Agent` macros)

## Next

- [Getting Started](getting_started.md)
- [Tool Calling With Actions](tool_calling_with_actions.md)
- [Configuration Reference](../developer/configuration_reference.md)
