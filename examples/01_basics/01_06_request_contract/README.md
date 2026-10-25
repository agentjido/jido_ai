# 01_06 — Request contract

Prepare and inspect one AI request before it runs. Then run it and inspect one
explicit result with ordered events.

## What you will learn

- `Agent.preflight/2` resolves the model, messages, visible tools, output, and
  limits without model or tool work.
- `visible_tools:` selects only tools declared by the Agent.
- `Agent.run/2` returns a completed or failed `Jido.AI.Result`.
- Every event has one request ID, run ID, sequence, and data Map.
- A direct AI request does not change Agent state.

## Prepare a request

```elixir
{:ok, request} =
  JidoAI.Examples.RequestContract.Agent.preflight(
    "Look up the project status.",
    visible_tools: [:lookup]
  )

Jido.AI.Request.visible_tool_names(request)
#=> ["lookup"]
```

The `calculate` tool remains in the Agent definition. It is not visible to this
request and a forged call to it is rejected before execution.

## Run a request

```elixir
{:ok, result} =
  JidoAI.Examples.RequestContract.Agent.run(
    "Reply with Ready.",
    visible_tools: []
  )

result.status
#=> :completed

Enum.map(result.events, & &1.type)
#=> [:request_started, :model_completed, :request_completed]
```

Use `generate/2` when only the output is needed. Use `reason/2` for a completed
result and the normal raw error contract. Use `run/2` when failure must also be
an explicit result.

## Commit rule

A direct request has `commit: :not_requested`. It cannot change Agent state.
For a routed turn, `Jido.AI.Turn.complete/4` accepts only a completed result,
builds candidate state and reply data, and returns route projection output.
Core Jido commits the candidate and builds the Reply Directive only after the
complete route Action succeeds.

## Run the example tests

```sh
mix test test/examples/01_basics/01_06_request_contract --include example --seed 0
```

The tests replace only the provider call. Request preparation, Flow execution,
result construction, and event order are real.
