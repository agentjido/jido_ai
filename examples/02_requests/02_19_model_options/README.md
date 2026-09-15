# 02_19 — Model and provider options

Select another provider for a later model call in one request.

## Read the code

Read [agent.ex](agent.ex), then [switch_probe.ex](switch_probe.ex), then [switch.ex](switch.ex).
Then read the matching tests below.

The source generates two AI Agents from one declaration to compare buffered
and streamed transport. A normal application needs only its selected form.

## Run it

From the package root:

```sh
mix test test/examples/02_requests/02_19_model_options --include example --seed 0
```

The default test path needs no credentials or remote provider. Model cases use
[the local HTTP/SSE server](../../support/mock_llm.ex) with real ReqLLM transport.
Shared setup and fault fixtures stay in [test support](../../../test/examples/support).

## Expected result and failure behavior

OpenAI and Anthropic calls retain their own request format and settings. Real tool results remain correlated across the provider change.

## Limits

The tests use local buffered and streaming responses. They do not verify remote-provider availability, every transport, or model answer quality.

## Files

- [02_19_model_options_test.exs](../../../test/examples/02_requests/02_19_model_options/02_19_model_options_test.exs)
- [Shared mock_llm.ex](../../support/mock_llm.ex)

Previous: [02_16](../02_16_typed_signals/README.md) | Next: [02_20](../02_20_call_counts/README.md)
