# Jido AI examples

This catalog starts with the smallest public Jido AI contract and grows one
working example at a time.

The previous example catalog is retained in
[`examples_v1/`](../examples_v1/README.md). It uses the previous Jido AI API and
does not compile as part of this catalog.

## Run

Run all current examples from the package root:

```sh
mix examples --seed 0
```

The example suite is offline. Live provider tests use `mix test.live` and are
not part of this catalog.

## Learning path

1. [Configure an AI response](01_basics/01_01_configure_response/README.md) —
   add `Jido.AI.Plugin` to a core Jido Agent and read its normalized response
   configuration.
