# Requests examples

These checked examples use the current Jido AI public contract. Each feature
keeps its source and detailed guide in one folder. Its tests live in the
matching `test/examples/02_requests` folder.

| Feature | Guide | Tests |
| --- | --- | --- |
| `02_01_session` | [02_01 — Request sessions](02_01_session/README.md) | [02_01_session_test.exs](../../test/examples/02_requests/02_01_session/02_01_session_test.exs) |
| `02_02_steering` | [02_02 — Steering and consumed history](02_02_steering/README.md) | [02_02_steering_test.exs](../../test/examples/02_requests/02_02_steering/02_02_steering_test.exs) |
| `02_11_completion` | [02_11: Completion commit and failure](02_11_completion/README.md) | [02_11_completion_test.exs](../../test/examples/02_requests/02_11_completion/02_11_completion_test.exs) |
| `02_13_tool_limits` | [02_13: Tool preflight and time limits](02_13_tool_limits/README.md) | [02_13_tool_limits_test.exs](../../test/examples/02_requests/02_13_tool_limits/02_13_tool_limits_test.exs) |
| `02_16_typed_signals` | [02_16: Typed Signals and Turn conversion](02_16_typed_signals/README.md) | [02_16_typed_signals_test.exs](../../test/examples/02_requests/02_16_typed_signals/02_16_typed_signals_test.exs) |
| `02_19_model_options` | [02_19: Request model and provider options](02_19_model_options/README.md) | [02_19_model_options_test.exs](../../test/examples/02_requests/02_19_model_options/02_19_model_options_test.exs) |
| `02_20_call_counts` | [02_20: Model operation counts after failure](02_20_call_counts/README.md) | [02_20_call_counts_test.exs](../../test/examples/02_requests/02_20_call_counts/02_20_call_counts_test.exs) |
| `02_22_request_inspection` | [02_22: Request inspection and saved trace prefixes](02_22_request_inspection/README.md) | [02_22_request_inspection_test.exs](../../test/examples/02_requests/02_22_request_inspection/02_22_request_inspection_test.exs) |
| `02_24_stream_usage` | [02_24: Stream usage sources](02_24_stream_usage/README.md) | [02_24_stream_usage_test.exs](../../test/examples/02_requests/02_24_stream_usage/02_24_stream_usage_test.exs) |
| `02_25_incomplete_response` | [02_25: Blank failures and partial response content](02_25_incomplete_response/README.md) | [02_25_incomplete_response_test.exs](../../test/examples/02_requests/02_25_incomplete_response/02_25_incomplete_response_test.exs) |
| `02_27_thread_session_values` | [02_27: Thread and Session values](02_27_thread_session_values/README.md) | [02_27_thread_session_values_test.exs](../../test/examples/02_requests/02_27_thread_session_values/02_27_thread_session_values_test.exs) |

Run this group from the repository root:

```sh
mix test test/examples/02_requests --include example --seed 0
```

See the [full example catalog](../README.md).
