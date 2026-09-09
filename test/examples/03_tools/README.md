# Tools example tests

These tests run the source examples in `examples/03_tools`. They use the
`:example` tag and do not run with the normal `mix test` command.

| Feature guide | Tests |
| --- | --- |
| [03_01_dynamic_catalog](../../../examples/03_tools/03_01_dynamic_catalog/README.md) | [03_01_dynamic_catalog_test.exs](03_01_dynamic_catalog/03_01_dynamic_catalog_test.exs) |
| [03_02_tool_context](../../../examples/03_tools/03_02_tool_context/README.md) | [03_02_tool_context_test.exs](03_02_tool_context/03_02_tool_context_test.exs) |
| [03_03_numeric_inputs](../../../examples/03_tools/03_03_numeric_inputs/README.md) | [03_03_numeric_inputs_test.exs](03_03_numeric_inputs/03_03_numeric_inputs_test.exs) |

Run this group from the repository root:

```sh
mix test test/examples/03_tools --include example --seed 0
```

See [all example tests](../README.md).
