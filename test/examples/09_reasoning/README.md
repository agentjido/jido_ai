# Reasoning example tests

These tests run the source examples in `examples/09_reasoning`. They use the
`:example` tag and do not run with the normal `mix test` command.

| Feature guide | Tests |
| --- | --- |
| [09_01_linear](../../../examples/09_reasoning/09_01_linear/README.md) | [09_01_linear_test.exs](09_01_linear/09_01_linear_test.exs) |
| [09_02_method_api](../../../examples/09_reasoning/09_02_method_api/README.md) | [09_02_method_api_test.exs](09_02_method_api/09_02_method_api_test.exs) |
| [09_03_aot](../../../examples/09_reasoning/09_03_aot/README.md) | [09_03_aot_test.exs](09_03_aot/09_03_aot_test.exs)<br>[aot_lifecycle_test.exs](09_03_aot/aot_lifecycle_test.exs) |
| [09_04_tot](../../../examples/09_reasoning/09_04_tot/README.md) | [09_04_tot_test.exs](09_04_tot/09_04_tot_test.exs) |
| [09_05_tot_api](../../../examples/09_reasoning/09_05_tot_api/README.md) | [09_05_tot_api_test.exs](09_05_tot_api/09_05_tot_api_test.exs) |
| [09_06_got](../../../examples/09_reasoning/09_06_got/README.md) | [09_06_got_test.exs](09_06_got/09_06_got_test.exs) |
| [09_07_got_api](../../../examples/09_reasoning/09_07_got_api/README.md) | [09_07_got_api_test.exs](09_07_got_api/09_07_got_api_test.exs) |
| [09_08_trm](../../../examples/09_reasoning/09_08_trm/README.md) | [09_08_trm_test.exs](09_08_trm/09_08_trm_test.exs) |
| [09_09_trm_api](../../../examples/09_reasoning/09_09_trm_api/README.md) | [09_09_trm_api_test.exs](09_09_trm_api/09_09_trm_api_test.exs) |
| [09_10_adaptive](../../../examples/09_reasoning/09_10_adaptive/README.md) | [09_10_adaptive_test.exs](09_10_adaptive/09_10_adaptive_test.exs) |
| [09_11_adaptive_api](../../../examples/09_reasoning/09_11_adaptive_api/README.md) | [09_11_adaptive_api_test.exs](09_11_adaptive_api/09_11_adaptive_api_test.exs) |
| [09_12_method_controls](../../../examples/09_reasoning/09_12_method_controls/README.md) | [09_12_method_controls_test.exs](09_12_method_controls/09_12_method_controls_test.exs) |
| [09_13_active_selection](../../../examples/09_reasoning/09_13_active_selection/README.md) | [09_13_active_selection_test.exs](09_13_active_selection/09_13_active_selection_test.exs) |
| [09_14_callable_reasoning](../../../examples/09_reasoning/09_14_callable_reasoning/README.md) | [09_14_callable_reasoning_test.exs](09_14_callable_reasoning/09_14_callable_reasoning_test.exs) |
| [09_15_prompt_policy](../../../examples/09_reasoning/09_15_prompt_policy/README.md) | [09_15_prompt_policy_test.exs](09_15_prompt_policy/09_15_prompt_policy_test.exs) |
| [09_16_reasoning_tool](../../../examples/09_reasoning/09_16_reasoning_tool/README.md) | [09_16_reasoning_tool_test.exs](09_16_reasoning_tool/09_16_reasoning_tool_test.exs) |

Run this group from the repository root:

```sh
mix test test/examples/09_reasoning --include example --seed 0
```

See [all example tests](../README.md).
