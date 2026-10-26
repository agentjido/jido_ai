# Results and Agent state

Model output, an AI request result, and committed Agent state are different
values.

During execution, model output becomes a portable `Jido.AI.ModelOutcome`.
`Jido.AI.Actions.InterpretOutcome` converts it to an `AgentDecision`. The Flow
then expands that decision into known graph nodes. Request state uses named
fields. It does not use one encoded private state value.

`generate/2` returns only accepted output:

```elixir
{:ok, text} = MyAgent.generate("Reply with Ready")
```

`reason/2` returns a completed result:

```elixir
{:ok, result} = MyAgent.reason("Reply with Ready")

result.status
#=> :completed

result.output
result.usage
result.events
```

`run/2` also returns an explicit result after execution failure:

```elixir
case MyAgent.run("Reply with Ready") do
  {:ok, %Jido.AI.Result{status: :completed} = result} -> result.output
  {:error, %Jido.AI.Result{} = result} -> {result.status, result.error}
  {:error, preparation_error} -> preparation_error
end
```

A direct request does not change Agent state. Its `commit` field is
`:not_requested`.

For a routed turn, call `Jido.AI.respond_result/3` and give the completed
result to `Jido.AI.Turn.complete/4`. This builds output for the route state and
reply projections. Core Jido validates the output, performs the final commit,
and builds the correlated Reply Directive.

If model work, output validation, or an output control fails, the turn Action
returns an error before candidate state exists. The prior Agent state remains
unchanged.

Tool work is different. An external tool effect can finish before final output
fails. Jido AI cannot undo that effect. Effectful tools need application
authorization and idempotency.
