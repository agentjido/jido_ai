# Resume example tests

These tests run the source examples in `examples/14_resume`. They use the
`:example` tag and do not run with the normal `mix test` command.

| Feature guide | Tests |
| --- | --- |
| [14_01_standalone_authoring](../../../examples/14_resume/14_01_standalone_authoring/README.md) | [14_01_standalone_authoring_test.exs](14_01_standalone_authoring/14_01_standalone_authoring_test.exs) |
| [14_02_standalone_runtime](../../../examples/14_resume/14_02_standalone_runtime/README.md) | [14_02_standalone_runtime_test.exs](14_02_standalone_runtime/14_02_standalone_runtime_test.exs) |
| [14_03_checkpoint_resume](../../../examples/14_resume/14_03_checkpoint_resume/README.md) | [14_03_checkpoint_resume_test.exs](14_03_checkpoint_resume/14_03_checkpoint_resume_test.exs) |
| [14_04_standalone_actions](../../../examples/14_resume/14_04_standalone_actions/README.md) | [14_04_standalone_actions_test.exs](14_04_standalone_actions/14_04_standalone_actions_test.exs) |
| [14_06_trace_and_cycles](../../../examples/14_resume/14_06_trace_and_cycles/README.md) | [14_06_trace_and_cycles_test.exs](14_06_trace_and_cycles/14_06_trace_and_cycles_test.exs) |
| [14_07_standalone_input](../../../examples/14_resume/14_07_standalone_input/README.md) | [14_07_standalone_input_test.exs](14_07_standalone_input/14_07_standalone_input_test.exs) |
| [14_08_query_append](../../../examples/14_resume/14_08_query_append/README.md) | [14_08_query_append_test.exs](14_08_query_append/14_08_query_append_test.exs) |
| [14_10_failure_position](../../../examples/14_resume/14_10_failure_position/README.md) | [14_10_failure_position_test.exs](14_10_failure_position/14_10_failure_position_test.exs) |
| [14_11_initial_state](../../../examples/14_resume/14_11_initial_state/README.md) | [14_11_initial_state_test.exs](14_11_initial_state/14_11_initial_state_test.exs) |
| [14_12_terminal_state](../../../examples/14_resume/14_12_terminal_state/README.md) | [14_12_terminal_state_test.exs](14_12_terminal_state/14_12_terminal_state_test.exs) |

Run this group from the repository root:

```sh
mix test test/examples/14_resume --include example --seed 0
```

See [all example tests](../README.md).
