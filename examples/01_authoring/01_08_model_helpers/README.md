# 01_08 — Model aliases with native ReqLLM calls

- [Alias implementation](../../../lib/jido_ai/models.ex)
- [Example tests](../../../test/examples/01_authoring/01_08_model_helpers/01_08_model_helpers_test.exs)

`Jido.AI.Models` has one job. It maps application names such as `:fast`,
`:capable`, and `:example` to native ReqLLM model inputs.

```elixir
model = Jido.AI.Models.resolve(:fast)
{:ok, response} = ReqLLM.generate_text(model, "Summarize this change.")
```

The examples test text, structured, and streaming calls through the public
ReqLLM API. Jido AI does not wrap provider calls or own generation defaults.
ReqLLM keeps its response, stream, option, header, usage, and error contracts.

The header cases have the `HIST-01/stream-headers` tag. They give partial
evidence for issue 212 and commits `8f669705` and `26bb4106`.
