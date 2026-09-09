# Authoring example tests

These tests run the source examples in `examples/01_authoring`. They use the
`:example` tag and do not run with the normal `mix test` command.

| Feature guide | Tests |
| --- | --- |
| [01_01_authoring_formats](../../../examples/01_authoring/01_01_authoring_formats/README.md) | [01_01_authoring_formats_test.exs](01_01_authoring_formats/01_01_authoring_formats_test.exs) |
| [01_02_tool_flow](../../../examples/01_authoring/01_02_tool_flow/README.md) | [01_02_tool_flow_test.exs](01_02_tool_flow/01_02_tool_flow_test.exs) |
| [01_03_structured_output](../../../examples/01_authoring/01_03_structured_output/README.md) | [01_03_structured_output_test.exs](01_03_structured_output/01_03_structured_output_test.exs) |
| [01_04_controls](../../../examples/01_authoring/01_04_controls/README.md) | [01_04_controls_test.exs](01_04_controls/01_04_controls_test.exs) |
| [01_05_streaming](../../../examples/01_authoring/01_05_streaming/README.md) | [01_05_streaming_test.exs](01_05_streaming/01_05_streaming_test.exs) |
| [01_06_ai_extension](../../../examples/01_authoring/01_06_ai_extension/README.md) | [01_06_ai_extension_test.exs](01_06_ai_extension/01_06_ai_extension_test.exs) |
| [01_07_ai_runtime](../../../examples/01_authoring/01_07_ai_runtime/README.md) | [01_07_ai_runtime_test.exs](01_07_ai_runtime/01_07_ai_runtime_test.exs) |
| [01_08_model_helpers](../../../examples/01_authoring/01_08_model_helpers/README.md) | [01_08_model_helpers_test.exs](01_08_model_helpers/01_08_model_helpers_test.exs) |

Run this group from the repository root:

```sh
mix test test/examples/01_authoring --include example --seed 0
```

See [all example tests](../README.md).
