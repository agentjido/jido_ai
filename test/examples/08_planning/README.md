# Planning example tests

These tests run the source examples in `examples/08_planning`. They use the
`:example` tag and do not run with the normal `mix test` command.

| Feature guide | Tests |
| --- | --- |
| [08_01_planning](../../../examples/08_planning/08_01_planning/README.md) | [08_01_planning_test.exs](08_01_planning/08_01_planning_test.exs) |

Run this group from the repository root:

```sh
mix test test/examples/08_planning --include example --seed 0
```

See [all example tests](../README.md).
