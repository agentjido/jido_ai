# Configuration Guide

This guide covers runtime configuration used by Jido.AI.

## Overview

There is no dedicated `Config` helper module in this project.
Configuration is handled through:

- `Jido.AI` functions (model alias resolution)
- application config (`config :jido_ai, ...`)
- ReqLLM provider config (`config :req_llm, ...`)

## Model Aliases (`:jido_ai`)

Jido.AI resolves model aliases through `Jido.AI.resolve_model/1`.

```elixir
Jido.AI.resolve_model(:fast)
# => "anthropic:claude-haiku-4-5"
```

Set aliases in app config:

```elixir
# config/config.exs
config :jido_ai,
  model_aliases: %{
    fast: "anthropic:claude-haiku-4-5",
    capable: "anthropic:claude-sonnet-4-20250514",
    reasoning: "anthropic:claude-sonnet-4-20250514",
    planning: "anthropic:claude-sonnet-4-20250514"
  }
```

Resolution behavior:

1. Built-in defaults are defined in `Jido.AI`.
2. `config :jido_ai, model_aliases: %{...}` overrides/extends defaults.
3. Unknown aliases raise `ArgumentError`.

## Provider Credentials (`:req_llm`)

Provider keys are consumed by ReqLLM.

```elixir
# config/runtime.exs (or config/config.exs)
config :req_llm,
  anthropic_api_key: System.get_env("ANTHROPIC_API_KEY"),
  openai_api_key: System.get_env("OPENAI_API_KEY"),
  google_api_key: System.get_env("GOOGLE_API_KEY"),
  mistral_api_key: System.get_env("MISTRAL_API_KEY")
```

You can also rely on environment variables directly (ReqLLM supports both).

## Optional Jido.AI Runtime Keys

```elixir
config :jido_ai,
  llm_client: MyApp.CustomLLMClient
```

- `:llm_client` lets you swap the client module used by `Jido.AI.LLMClient`.
- The module should implement the callbacks expected by `Jido.AI.LLMClient`.

## Usage in Strategies and Actions

```elixir
use Jido.AI.ReActAgent,
  name: "my_agent",
  model: :fast,
  tools: [MyApp.Actions.Calculator]
```

Aliases can also be used in directives/actions that accept `model_alias` or `model`.

## Validation Tip

Run a quick sanity check in `iex -S mix`:

```elixir
Jido.AI.model_aliases()
Jido.AI.resolve_model(:fast)
```

If alias resolution works and ReqLLM keys are present, LLM actions are ready to run.
