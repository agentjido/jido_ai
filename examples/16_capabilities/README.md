# Capabilities examples

These checked examples use the current Jido AI public contract. Each feature
keeps its source and detailed guide in one folder. Its tests live in the
matching `test/examples/16_capabilities` folder.

| Feature | Guide | Tests |
| --- | --- | --- |
| `16_01_reasoning` | [16_01 — Reasoning capability Plugins](16_01_reasoning/README.md) | [16_01_reasoning_test.exs](../../test/examples/16_capabilities/16_01_reasoning/16_01_reasoning_test.exs) |
| `16_02_chat` | [Chat capability and callable Actions](16_02_chat/README.md) | [16_02_chat_test.exs](../../test/examples/16_capabilities/16_02_chat/16_02_chat_test.exs) |
| `16_03_routing_policy` | [ModelRouting and Policy](16_03_routing_policy/README.md) | [16_03_routing_policy_test.exs](../../test/examples/16_capabilities/16_03_routing_policy/16_03_routing_policy_test.exs) |
| `16_04_plugin_stack` | [Default Plugins on public AI Agents](16_04_plugin_stack/README.md) | [16_04_plugin_stack_test.exs](../../test/examples/16_capabilities/16_04_plugin_stack/16_04_plugin_stack_test.exs) |

Run this group from the repository root:

```sh
mix test test/examples/16_capabilities --include example --seed 0
```

See the [full example catalog](../README.md).
