# 02_19: Model and Provider Options

This example changes the model provider inside one request. The first and third
calls use the declared OpenAI model. A request transformer selects Anthropic
for the second call. Real tool results cross both provider wire formats.

The four cases cover native and standalone execution with buffered and
streaming model calls. They check request paths, headers, model labels, usage,
tool call IDs, and portable final state.

```sh
mix test test/examples/02_requests/02_19_model_options --include example --seed 0
```
