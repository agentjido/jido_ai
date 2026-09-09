# Requests examples

These checked examples use the current Jido AI public contract. Each feature
keeps its source and detailed guide in one folder. Its tests live in the
matching `test/examples/02_requests` folder.

| Feature | Guide | Tests |
| --- | --- | --- |
| `02_01_session` | [02_01 — Request sessions](02_01_session/README.md) | [02_01_session_test.exs](../../test/examples/02_requests/02_01_session/02_01_session_test.exs) |
| `02_02_steering` | [02_02 — Steering and consumed history](02_02_steering/README.md) | [02_02_steering_test.exs](../../test/examples/02_requests/02_02_steering/02_02_steering_test.exs) |
| `02_03_public_agent` | [02_03: Public Agent helpers](02_03_public_agent/README.md) | [02_03_public_agent_test.exs](../../test/examples/02_requests/02_03_public_agent/02_03_public_agent_test.exs) |
| `02_04_request_scope` | [02_04: Request-specific tools, output and limits](02_04_request_scope/README.md) | [02_04_request_scope_test.exs](../../test/examples/02_requests/02_04_request_scope/02_04_request_scope_test.exs) |
| `02_05_request_transform` | [02_05: Request transformation and output repair](02_05_request_transform/README.md) | [02_05_request_transform_test.exs](../../test/examples/02_requests/02_05_request_transform/02_05_request_transform_test.exs) |
| `02_06_output_contract` | [02_06: Output validation, events and metadata](02_06_output_contract/README.md) | [02_06_output_contract_test.exs](../../test/examples/02_requests/02_06_output_contract/02_06_output_contract_test.exs) |
| `02_07_response_metadata` | [02_07: Model response metadata](02_07_response_metadata/README.md) | [02_07_response_metadata_test.exs](../../test/examples/02_requests/02_07_response_metadata/02_07_response_metadata_test.exs) |
| `02_08_error_contract` | [02_08: Errors through core execution](02_08_error_contract/README.md) | [02_08_error_contract_test.exs](../../test/examples/02_requests/02_08_error_contract/02_08_error_contract_test.exs) |
| `02_09_tool_results` | [02_09: Tool results and request inspection](02_09_tool_results/README.md) | [02_09_tool_results_test.exs](../../test/examples/02_requests/02_09_tool_results/02_09_tool_results_test.exs) |
| `02_10_tool_effects` | [02_10: Tool effects and complete candidate state](02_10_tool_effects/README.md) | [02_10_tool_effects_test.exs](../../test/examples/02_requests/02_10_tool_effects/02_10_tool_effects_test.exs) |
| `02_11_completion` | [02_11: Completion commit and failure](02_11_completion/README.md) | [02_11_completion_test.exs](../../test/examples/02_requests/02_11_completion/02_11_completion_test.exs) |
| `02_12_tool_callbacks` | [02_12: Tool callbacks and request state](02_12_tool_callbacks/README.md) | [02_12_tool_callbacks_test.exs](../../test/examples/02_requests/02_12_tool_callbacks/02_12_tool_callbacks_test.exs) |
| `02_13_tool_limits` | [02_13: Tool preflight and time limits](02_13_tool_limits/README.md) | [02_13_tool_limits_test.exs](../../test/examples/02_requests/02_13_tool_limits/02_13_tool_limits_test.exs) |
| `02_14_stream_activity` | [02_14: Stream activity and tool keepalives](02_14_stream_activity/README.md) | [02_14_stream_activity_test.exs](../../test/examples/02_requests/02_14_stream_activity/02_14_stream_activity_test.exs) |
| `02_15_early_tool_activity` | [02_15: Early tool activity and delta capture](02_15_early_tool_activity/README.md) | [02_15_early_tool_activity_test.exs](../../test/examples/02_requests/02_15_early_tool_activity/02_15_early_tool_activity_test.exs) |
| `02_16_typed_signals` | [02_16: Typed Signals and Turn conversion](02_16_typed_signals/README.md) | [02_16_typed_signals_test.exs](../../test/examples/02_requests/02_16_typed_signals/02_16_typed_signals_test.exs) |
| `02_17_signal_delivery` | [02_17: Automatic session Signal delivery](02_17_signal_delivery/README.md) | [02_17_signal_delivery_test.exs](../../test/examples/02_requests/02_17_signal_delivery/02_17_signal_delivery_test.exs) |
| `02_18_admission` | [02_18: Request admission events](02_18_admission/README.md) | [02_18_admission_test.exs](../../test/examples/02_requests/02_18_admission/02_18_admission_test.exs) |
| `02_19_model_options` | [02_19: Request model and provider options](02_19_model_options/README.md) | [02_19_model_options_test.exs](../../test/examples/02_requests/02_19_model_options/02_19_model_options_test.exs) |
| `02_20_call_counts` | [02_20: Model operation counts after failure](02_20_call_counts/README.md) | [02_20_call_counts_test.exs](../../test/examples/02_requests/02_20_call_counts/02_20_call_counts_test.exs) |
| `02_21_context_views` | [02_21: Public context views and history changes](02_21_context_views/README.md) | [02_21_context_views_test.exs](../../test/examples/02_requests/02_21_context_views/02_21_context_views_test.exs) |
| `02_22_request_inspection` | [02_22: Request inspection and saved trace prefixes](02_22_request_inspection/README.md) | [02_22_request_inspection_test.exs](../../test/examples/02_requests/02_22_request_inspection/02_22_request_inspection_test.exs) |
| `02_23_context_operations` | [02_23: Context operations and lane history](02_23_context_operations/README.md) | [02_23_context_operations_test.exs](../../test/examples/02_requests/02_23_context_operations/02_23_context_operations_test.exs) |
| `02_24_stream_usage` | [02_24: Stream usage sources](02_24_stream_usage/README.md) | [02_24_stream_usage_test.exs](../../test/examples/02_requests/02_24_stream_usage/02_24_stream_usage_test.exs) |
| `02_25_incomplete_response` | [02_25: Blank failures and partial response content](02_25_incomplete_response/README.md) | [02_25_incomplete_response_test.exs](../../test/examples/02_requests/02_25_incomplete_response/02_25_incomplete_response_test.exs) |
| `02_26_request_setup` | [02_26: Declared and request options](02_26_request_setup/README.md) | [02_26_request_setup_test.exs](../../test/examples/02_requests/02_26_request_setup/02_26_request_setup_test.exs) |
| `02_27_thread_session_values` | [02_27: Thread and Session values](02_27_thread_session_values/README.md) | [02_27_thread_session_values_test.exs](../../test/examples/02_requests/02_27_thread_session_values/02_27_thread_session_values_test.exs) |

Run this group from the repository root:

```sh
mix test test/examples/02_requests --include example --seed 0
```

See the [full example catalog](../README.md).
