# Reasoning examples

These checked examples use the current Jido AI public contract. Each feature
keeps its source and detailed guide in one folder. Its tests live in the
matching `test/examples/09_reasoning` folder.

| Feature | Guide | Tests |
| --- | --- | --- |
| `09_01_linear` | [09_01 — CoT and CoD through the shared Flow](09_01_linear/README.md) | [09_01_linear_test.exs](../../test/examples/09_reasoning/09_01_linear/09_01_linear_test.exs) |
| `09_02_method_api` | [09_02 — Linear method selection and retained data APIs](09_02_method_api/README.md) | [09_02_method_api_test.exs](../../test/examples/09_reasoning/09_02_method_api/09_02_method_api_test.exs) |
| `09_03_aot` | [09_03 — Algorithm of Thoughts through the shared Flow](09_03_aot/README.md) | [09_03_aot_test.exs](../../test/examples/09_reasoning/09_03_aot/09_03_aot_test.exs)<br>[aot_lifecycle_test.exs](../../test/examples/09_reasoning/09_03_aot/aot_lifecycle_test.exs) |
| `09_04_tot` | [09_04 — Tree of Thoughts through core Flow](09_04_tot/README.md) | [09_04_tot_test.exs](../../test/examples/09_reasoning/09_04_tot/09_04_tot_test.exs) |
| `09_05_tot_api` | [Public Tree of Thoughts and tool callbacks](09_05_tot_api/README.md) | [09_05_tot_api_test.exs](../../test/examples/09_reasoning/09_05_tot_api/09_05_tot_api_test.exs) |
| `09_06_got` | [Graph of Thoughts through the shared Flow](09_06_got/README.md) | [09_06_got_test.exs](../../test/examples/09_reasoning/09_06_got/09_06_got_test.exs) |
| `09_07_got_api` | [Public GoT helpers and graph inspection](09_07_got_api/README.md) | [09_07_got_api_test.exs](../../test/examples/09_reasoning/09_07_got_api/09_07_got_api_test.exs) |
| `09_08_trm` | [TRM through the shared Flow](09_08_trm/README.md) | [09_08_trm_test.exs](../../test/examples/09_reasoning/09_08_trm/09_08_trm_test.exs) |
| `09_09_trm_api` | [Public TRM helpers on v3](09_09_trm_api/README.md) | [09_09_trm_api_test.exs](../../test/examples/09_reasoning/09_09_trm_api/09_09_trm_api_test.exs) |
| `09_10_adaptive` | [Adaptive selection through the shared Flow](09_10_adaptive/README.md) | [09_10_adaptive_test.exs](../../test/examples/09_reasoning/09_10_adaptive/09_10_adaptive_test.exs) |
| `09_11_adaptive_api` | [Public Adaptive Agent API](09_11_adaptive_api/README.md) | [09_11_adaptive_api_test.exs](../../test/examples/09_reasoning/09_11_adaptive_api/09_11_adaptive_api_test.exs) |
| `09_12_method_controls` | [Resolve method defaults at request start](09_12_method_controls/README.md) | [09_12_method_controls_test.exs](../../test/examples/09_reasoning/09_12_method_controls/09_12_method_controls_test.exs) |
| `09_13_active_selection` | [Inspect Adaptive selection during a request](09_13_active_selection/README.md) | [09_13_active_selection_test.exs](../../test/examples/09_reasoning/09_13_active_selection/09_13_active_selection_test.exs) |
| `09_14_callable_reasoning` | [Callable reasoning through v3 Exec](09_14_callable_reasoning/README.md) | [09_14_callable_reasoning_test.exs](../../test/examples/09_reasoning/09_14_callable_reasoning/09_14_callable_reasoning_test.exs) |
| `09_15_prompt_policy` | [09_15: Adaptive prompt selection](09_15_prompt_policy/README.md) | [09_15_prompt_policy_test.exs](../../test/examples/09_reasoning/09_15_prompt_policy/09_15_prompt_policy_test.exs) |
| `09_16_reasoning_tool` | [09_16: Reasoning as a raw model tool](09_16_reasoning_tool/README.md) | [09_16_reasoning_tool_test.exs](../../test/examples/09_reasoning/09_16_reasoning_tool/09_16_reasoning_tool_test.exs) |

Run this group from the repository root:

```sh
mix test test/examples/09_reasoning --include example --seed 0
```

See the [full example catalog](../README.md).
