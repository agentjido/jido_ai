# Requests example tests

These tests run the source examples in `examples/02_requests`. They use the
`:example` tag and do not run with the normal `mix test` command.

| Feature guide | Tests |
| --- | --- |
| [02_01_session](../../../examples/02_requests/02_01_session/README.md) | [02_01_session_test.exs](02_01_session/02_01_session_test.exs) |
| [02_02_steering](../../../examples/02_requests/02_02_steering/README.md) | [02_02_steering_test.exs](02_02_steering/02_02_steering_test.exs) |
| [02_11_completion](../../../examples/02_requests/02_11_completion/README.md) | [02_11_completion_test.exs](02_11_completion/02_11_completion_test.exs) |
| [02_13_tool_limits](../../../examples/02_requests/02_13_tool_limits/README.md) | [02_13_tool_limits_test.exs](02_13_tool_limits/02_13_tool_limits_test.exs) |
| [02_16_typed_signals](../../../examples/02_requests/02_16_typed_signals/README.md) | [02_16_typed_signals_test.exs](02_16_typed_signals/02_16_typed_signals_test.exs) |
| [02_19_model_options](../../../examples/02_requests/02_19_model_options/README.md) | [02_19_model_options_test.exs](02_19_model_options/02_19_model_options_test.exs) |
| [02_20_call_counts](../../../examples/02_requests/02_20_call_counts/README.md) | [02_20_call_counts_test.exs](02_20_call_counts/02_20_call_counts_test.exs) |
| [02_22_request_inspection](../../../examples/02_requests/02_22_request_inspection/README.md) | [02_22_request_inspection_test.exs](02_22_request_inspection/02_22_request_inspection_test.exs) |
| [02_24_stream_usage](../../../examples/02_requests/02_24_stream_usage/README.md) | [02_24_stream_usage_test.exs](02_24_stream_usage/02_24_stream_usage_test.exs) |
| [02_25_incomplete_response](../../../examples/02_requests/02_25_incomplete_response/README.md) | [02_25_incomplete_response_test.exs](02_25_incomplete_response/02_25_incomplete_response_test.exs) |
| [02_27_thread_session_values](../../../examples/02_requests/02_27_thread_session_values/README.md) | [02_27_thread_session_values_test.exs](02_27_thread_session_values/02_27_thread_session_values_test.exs) |

Run this group from the repository root:

```sh
mix test test/examples/02_requests --include example --seed 0
```

See [all example tests](../README.md).
