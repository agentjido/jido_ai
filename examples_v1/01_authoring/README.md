# Authoring examples

Read the table from top to bottom for the learning order. Gaps in the IDs
are intentional; the remaining examples keep their published IDs.

These checked examples use the current Jido AI public contract. Each feature
keeps its source and detailed guide in one folder. Its tests live in the
matching `test/examples/01_authoring` folder.

Start with one answer, tools, structured output, controls, and streaming.
Then read extension composition, the combined runtime example, and direct model
helpers. Folder IDs stay unchanged; 01_01 now teaches the basic AI DSL path.

| Feature | Guide | Tests |
| --- | --- | --- |
| `01_01_authoring_formats` | [01_01 — One AI answer](01_01_authoring_formats/README.md) | [01_01_authoring_formats_test.exs](../../test/examples/01_authoring/01_01_authoring_formats/01_01_authoring_formats_test.exs) |
| `01_02_tool_flow` | [01_02 — Action and Flow tools](01_02_tool_flow/README.md) | [01_02_tool_flow_test.exs](../../test/examples/01_authoring/01_02_tool_flow/01_02_tool_flow_test.exs) |
| `01_03_structured_output` | [01_03 — Structured output](01_03_structured_output/README.md) | [01_03_structured_output_test.exs](../../test/examples/01_authoring/01_03_structured_output/01_03_structured_output_test.exs) |
| `01_04_controls` | [01_04 — Controls](01_04_controls/README.md) | [01_04_controls_test.exs](../../test/examples/01_authoring/01_04_controls/01_04_controls_test.exs) |
| `01_05_streaming` | [01_05 — Streaming and cancellation](01_05_streaming/README.md) | [01_05_streaming_test.exs](../../test/examples/01_authoring/01_05_streaming/01_05_streaming_test.exs) |
| `01_06_ai_extension` | [01_06 — AI authoring extension](01_06_ai_extension/README.md) | [01_06_ai_extension_test.exs](../../test/examples/01_authoring/01_06_ai_extension/01_06_ai_extension_test.exs) |
| `01_07_ai_runtime` | [01_07 — Production AI runtime](01_07_ai_runtime/README.md) | [01_07_ai_runtime_test.exs](../../test/examples/01_authoring/01_07_ai_runtime/01_07_ai_runtime_test.exs) |
| `01_08_model_helpers` | [01_08 — Shared public model helpers](01_08_model_helpers/README.md) | [01_08_model_helpers_test.exs](../../test/examples/01_authoring/01_08_model_helpers/01_08_model_helpers_test.exs) |

Run this group from the repository root:

```sh
mix test test/examples/01_authoring --include example --seed 0
```

See the [full example catalog](../README.md).
