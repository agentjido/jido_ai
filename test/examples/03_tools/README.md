# Tools example tests

These tests run the source examples in `examples/03_tools`. They use the
`:example` tag and do not run with the normal `mix test` command.

| Feature guide | Tests |
| --- | --- |
| [03_03_numeric_inputs](../../../examples/03_tools/03_03_numeric_inputs/README.md) | [03_03_numeric_inputs_test.exs](03_03_numeric_inputs/03_03_numeric_inputs_test.exs) |

Run this group from the repository root:

```sh
mix test test/examples/03_tools --include example --seed 0
```

See [all example tests](../README.md).
