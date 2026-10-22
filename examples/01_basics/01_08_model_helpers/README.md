# 01_08 — Model helpers

Use a local alias or a direct ReqLLM model name.

## What you will learn

- Configure aliases with `config :jido_ai, :model_aliases`.
- Resolve aliases with `Jido.AI.Models.resolve/1`.
- Keep a direct provider model name unchanged.
- Get an explicit error for an unknown alias.

## Run it

```sh
mix test test/examples/01_basics/01_08_model_helpers --include example --seed 0
```

Aliases are application configuration. They are resolved when a request
starts, not when the Agent module compiles.

## Files

- [Agents](models.ex)
- [Test](../../../test/examples/01_basics/01_08_model_helpers/model_helpers_test.exs)
