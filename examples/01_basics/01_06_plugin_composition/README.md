# 01_06 — Plug-in composition

Add `Jido.AI.Plugin` to a core Jido Agent directly.

## What you will learn

- Use `Jido.Agent` with `extensions: [Jido.AI.Plugin]`.
- Use the same top-level `ai` block as `Jido.AI.Agent`.
- Treat `Jido.AI.Agent` as a small convenience wrapper, not a second Agent type.

## Run it

```sh
mix test test/examples/01_basics/01_06_plugin_composition --include example --seed 0
```

The test is offline. It checks the normalized Agent definition only.

Use `Jido.AI.Agent` for the usual form. Use explicit plug-in composition when
an application builds its own Agent wrapper or manages extension order itself.

## Files

- [Agents](agents.ex)
- [Test](../../../test/examples/01_basics/01_06_plugin_composition/plugin_composition_test.exs)
