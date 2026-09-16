# Resume examples

Read the table from top to bottom for the learning order. Gaps in the IDs
are intentional; the remaining examples keep their published IDs.

These checked examples use the current Jido AI public contract. Each feature
keeps its source and detailed guide in one folder. Its tests live in the
matching `test/examples/14_resume` folder.

| Feature | Guide | Tests |
| --- | --- | --- |
| `14_01_standalone_authoring` | [14_01: Standalone configuration and token foundation](14_01_standalone_authoring/README.md) | [14_01_standalone_authoring_test.exs](../../test/examples/14_resume/14_01_standalone_authoring/14_01_standalone_authoring_test.exs) |
| `14_02_standalone_runtime` | [14_02: Public standalone runtime](14_02_standalone_runtime/README.md) | [14_02_standalone_runtime_test.exs](../../test/examples/14_resume/14_02_standalone_runtime/14_02_standalone_runtime_test.exs) |
| `14_03_checkpoint_resume` | [14_03: Model and tool checkpoint resume](14_03_checkpoint_resume/README.md) | [14_03_checkpoint_resume_test.exs](../../test/examples/14_resume/14_03_checkpoint_resume/14_03_checkpoint_resume_test.exs) |
| `14_04_standalone_actions` | [14_04: Standalone ReAct Actions](14_04_standalone_actions/README.md) | [14_04_standalone_actions_test.exs](../../test/examples/14_resume/14_04_standalone_actions/14_04_standalone_actions_test.exs) |
| `14_06_trace_and_cycles` | [14_06: Trace controls and repeated tool calls](14_06_trace_and_cycles/README.md) | [14_06_trace_and_cycles_test.exs](../../test/examples/14_resume/14_06_trace_and_cycles/14_06_trace_and_cycles_test.exs) |
| `14_07_standalone_input` | [14_07: Caller-supplied input queues](14_07_standalone_input/README.md) | [14_07_standalone_input_test.exs](../../test/examples/14_resume/14_07_standalone_input/14_07_standalone_input_test.exs) |
| `14_08_query_append` | [14_08: Native query append and State counters](14_08_query_append/README.md) | [14_08_query_append_test.exs](../../test/examples/14_resume/14_08_query_append/14_08_query_append_test.exs) |
| `14_10_failure_position` | [14_10: Reasoning position on failure and cancellation](14_10_failure_position/README.md) | [14_10_failure_position_test.exs](../../test/examples/14_resume/14_10_failure_position/14_10_failure_position_test.exs) |
| `14_11_initial_state` | [14_11: Initial context state import](14_11_initial_state/README.md) | [14_11_initial_state_test.exs](../../test/examples/14_resume/14_11_initial_state/14_11_initial_state_test.exs) |
| `14_12_terminal_state` | [14_12: Native terminal state restore](14_12_terminal_state/README.md) | [14_12_terminal_state_test.exs](../../test/examples/14_resume/14_12_terminal_state/14_12_terminal_state_test.exs) |

Run this group from the repository root:

```sh
mix test test/examples/14_resume --include example --seed 0
```

See the [full example catalog](../README.md).
