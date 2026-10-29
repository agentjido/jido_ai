# Proposed — Plug-in composition

Add `Jido.AI.Plugin` to a core Jido Agent directly.

This example is outside the ordered learning path. It is a candidate for the
planned Agent composition lesson.

## What you will learn

- Use `Jido.Agent` with `plugins: [Jido.AI.Agent.Plugin]`.
- Use the same top-level `ai` block as `Jido.AI.Agent`.
- Treat `Jido.AI.Agent` as a small convenience wrapper, not a second Agent
  type.

## Run it

```sh
mix test test/examples/99_proposed/plugin_composition --include example --seed 0
```

The test is offline. It checks the normalized Agent definition only.

Use `Jido.AI.Agent` for the usual form. Use explicit plug-in composition when
an application builds its own Agent wrapper or manages extension order itself.

## Files

- [Agents](agents.ex)
- [Test](../../../test/examples/99_proposed/plugin_composition/plugin_composition_test.exs)
