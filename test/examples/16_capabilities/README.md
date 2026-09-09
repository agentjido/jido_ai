# Capabilities example tests

These tests run the source examples in `examples/16_capabilities`. They use the
`:example` tag and do not run with the normal `mix test` command.

| Feature guide | Tests |
| --- | --- |
| [16_01_reasoning](../../../examples/16_capabilities/16_01_reasoning/README.md) | [16_01_reasoning_test.exs](16_01_reasoning/16_01_reasoning_test.exs) |
| [16_02_chat](../../../examples/16_capabilities/16_02_chat/README.md) | [16_02_chat_test.exs](16_02_chat/16_02_chat_test.exs) |
| [16_03_routing_policy](../../../examples/16_capabilities/16_03_routing_policy/README.md) | [16_03_routing_policy_test.exs](16_03_routing_policy/16_03_routing_policy_test.exs) |
| [16_04_plugin_stack](../../../examples/16_capabilities/16_04_plugin_stack/README.md) | [16_04_plugin_stack_test.exs](16_04_plugin_stack/16_04_plugin_stack_test.exs) |

Run this group from the repository root:

```sh
mix test test/examples/16_capabilities --include example --seed 0
```

See [all example tests](../README.md).
