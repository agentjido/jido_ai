# Request Lifecycle And Concurrency

You need concurrent requests without single-slot state overwrites.

After this guide, you will use request handles (`ask/await`) and collect multiple results safely.

## Core Pattern

`Jido.AI.Request` follows a `Task.async/await` style model:

```elixir
{:ok, req1} = MyApp.MathAgent.ask(pid, "2 + 2")
{:ok, req2} = MyApp.MathAgent.ask(pid, "3 + 3")

{:ok, r1} = MyApp.MathAgent.await(req1)
{:ok, r2} = MyApp.MathAgent.await(req2)
```

Per-request ReAct overrides travel with the request handle:

```elixir
{:ok, req3} =
  MyApp.MathAgent.ask(pid, "Search only",
    allowed_tools: ["search"],
    tool_context: %{tenant_id: "acme"}
  )
```

## Steering An Active ReAct Run

`ask/await` remains the request API. Mid-run steering is a separate control path:

```elixir
{:ok, request} = MyApp.MathAgent.ask(pid, "Work on Q1")

{:ok, _agent} = MyApp.MathAgent.steer(pid, "Actually prioritize Q2", expected_request_id: request.id)

{:ok, result} = MyApp.MathAgent.await(request)
```

Use:
- `steer/3` for user-visible follow-up input on an active ReAct run
- `inject/3` for programmatic or inter-agent input on an active ReAct run

Important:
- neither `steer/3` nor `inject/3` creates a new request handle
- both reject idle agents with `{:error, {:rejected, :idle}}`
- successful `steer/3` / `inject/3` means the input was queued, not durably persisted
- if the run terminates before the runtime drains queued input, that input is dropped
- normal concurrent `ask/3` calls still busy-reject while a ReAct run is active
- steering is ReAct-only in this version

## Runtime Contract Map

- `Jido.AI.Request`: request handles, `await/2`, `await_many/2`, request state lifecycle.
- `Jido.AI.Turn`: normalized response shape and assistant/tool message projection.
- `Jido.AI.Context`: conversation accumulation and context projection for follow-up turns.
- `Jido.AI.steer/3` and `Jido.AI.inject/3`: explicit control path for active ReAct runs.
- Directive runtime behavior is documented in [Directives Runtime Contract](../developer/directives_runtime_contract.md).

## Await Many

```elixir
handles =
  ["2 + 2", "5 + 5", "8 + 8"]
  |> Enum.map(fn q -> elem(MyApp.MathAgent.ask(pid, q), 1) end)

results = Jido.AI.Request.await_many(handles, timeout: 30_000)
# [{:ok, ...}, {:ok, ...}, {:error, ...}]
```

## Runtime End-To-End Snippet

```elixir
alias Jido.AI.{Context, Turn}

{:ok, request} = MyApp.MathAgent.ask(pid, "What is 2 + 2?")

context =
  Context.new(system_prompt: "You are concise.")
  |> Context.append_user("What is 2 + 2?")

case MyApp.MathAgent.await(request, timeout: 15_000) do
  {:ok, result_text} ->
    turn = Turn.from_result_map(%{type: :final_answer, text: result_text})

    updated_context =
      context
      |> Context.append_assistant(turn.text)

    Context.to_messages(updated_context)

  {:error, {:rejected, :busy, message}} ->
    IO.puts("Request rejected: #{message}")

  {:error, :timeout} ->
    IO.puts("Request timed out")
end
```

## Lifecycle States

Each request is tracked with status like:
- `:pending`
- `:completed`
- `:failed`
- `:timeout`

Agent state keeps request maps and compatibility fields (`last_query`, `last_answer`, etc.).

## Failure Mode: Timeouts Under Load

Symptom:
- frequent `{:error, :timeout}` from `await/2`

Fix:
- increase await timeout for expensive workloads
- lower `max_iterations` for ReAct-style loops
- reduce concurrency burst size or shard traffic

## Defaults You Should Know

- Default await timeout: `30_000ms`
- Default tracked request retention: `100` (evicts older entries)

## When To Use / Not Use

Use this pattern when:
- multiple caller processes can query the same agent
- you need precise correlation from submission to result

Do not use this pattern when:
- you only run single sequential calls and can tolerate sync wrappers

## Next

- [Context And Message Projection](thread_context_and_message_projection.md)
- [Observability Basics](observability_basics.md)
- [Architecture And Runtime Flow](../developer/architecture_and_runtime_flow.md)
