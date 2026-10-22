# 01_04 — Input and output controls

Run a local check before the request and after the response.

## What you will learn

- Declare input and output Jido Actions in a `controls` block.
- Use either an Action module or an inline Action.
- Set request limits in the same block.
- Pass Action context with the `:jido_context` option.
- Stop a denied request before it reaches ReqLLM.
- Reject a model result that does not pass the output check.

## Run it

```sh
mix test test/examples/01_basics/01_04_controls --include example --seed 0
```

Controls are normal Jido Actions. Jido Exec validates and runs them. The input
control uses an Action module. The output control uses `output_action` to
compile an ordinary inline Action. They do not depend on a provider.

## Files

- [Agent and controls](agent.ex)
- [Test](../../../test/examples/01_basics/01_04_controls/controls_test.exs)
