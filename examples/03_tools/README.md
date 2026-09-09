# Tools examples

These checked examples use the current Jido AI public contract. Each feature
keeps its source and detailed guide in one folder. Its tests live in the
matching `test/examples/03_tools` folder.

| Feature | Guide | Tests |
| --- | --- | --- |
| `03_01_dynamic_catalog` | [03_01: Dynamic tools and prompts](03_01_dynamic_catalog/README.md) | [03_01_dynamic_catalog_test.exs](../../test/examples/03_tools/03_01_dynamic_catalog/03_01_dynamic_catalog_test.exs) |
| `03_02_tool_context` | [03_02: Persistent tool context](03_02_tool_context/README.md) | [03_02_tool_context_test.exs](../../test/examples/03_tools/03_02_tool_context/03_02_tool_context_test.exs) |
| `03_03_numeric_inputs` | [03_03: Numeric tool inputs](03_03_numeric_inputs/README.md) | [03_03_numeric_inputs_test.exs](../../test/examples/03_tools/03_03_numeric_inputs/03_03_numeric_inputs_test.exs) |

Run this group from the repository root:

```sh
mix test test/examples/03_tools --include example --seed 0
```

See the [full example catalog](../README.md).
