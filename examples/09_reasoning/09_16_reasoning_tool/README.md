# 09_16 — Reasoning as a model tool

Expose `RunStrategy` directly as a model-callable Action.

## What you will learn

- Export a prompt-only tool schema. The model cannot select execution policy.
- Bind a resolved `Jido.AI.Profile` under `:jido_ai_callable_profile` in the
  request context and explicitly forward that binding to the tool.
- Cancel nested work without stopping the outer Agent.

## Read the code

Read [agent.ex](agent.ex).
Then read the matching tests below.

## Run it

From the package root:

```sh
mix test test/examples/09_reasoning/09_16_reasoning_tool --include example --seed 0
```

The default test path needs no credentials or remote provider. Model cases use
[the local HTTP/SSE server](../../support/mock_llm.ex) with real ReqLLM transport.
Shared setup and fault fixtures stay in [test support](../../../test/examples/support).

Bind each transport by its Profile ID. The outer Profile is `:assistant`; the
tests bind the callable Profile as `:review`:

```elixir
context = %{
  jido_ai_callable_profile: profile,
  ai: %{
    assistant: %{options: JidoAI.Examples.MockLLM.options(mock)},
    review: %{options: JidoAI.Examples.MockLLM.options(mock)}
  }
}
```

The tests consume the complete local script. They also prove that the nested
call uses the outer quota and survives Builder and source JSON construction.

## Expected result and failure behavior

The outer request receives the real inner method result and uses it in its next model call. Cancellation stops inner work. Invalid tool input fails before execution.

## Limits

The host selects the inner method, model, and limits in the Profile. The tool
accepts only a prompt. The binding stays outside model arguments and durable
state. Nested work still needs explicit budgets. Complete method and schema
matrices belong to unit and authoring tests. Dynamic tool sources remain deferred.

## Files

- [09_16_reasoning_tool_test.exs](../../../test/examples/09_reasoning/09_16_reasoning_tool/09_16_reasoning_tool_test.exs)
- [Shared mock_llm.ex](../../support/mock_llm.ex)

Previous: [09_14](../09_14_callable_reasoning/README.md)
