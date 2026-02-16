# Streaming Workflows

You need token-level output, optional buffering, and predictable stream lifecycle handling.

After this guide, you can start streams, process chunks, and finalize streams using built-in streaming actions.

## Start A Stream

```elixir
{:ok, start_result} =
  Jido.Exec.run(Jido.AI.Actions.Streaming.StartStream, %{
    model: :fast,
    prompt: "Write a 3-line summary of OTP supervision",
    buffer: true,
    auto_process: false
  })

stream_id = start_result.stream_id
```

## Process Tokens

```elixir
{:ok, _processed} =
  Jido.Exec.run(Jido.AI.Actions.Streaming.ProcessTokens, %{
    stream_id: stream_id,
    on_token: fn token -> IO.write(token) end
  })
```

## Finalize And Inspect

```elixir
{:ok, done} =
  Jido.Exec.run(Jido.AI.Actions.Streaming.EndStream, %{
    stream_id: stream_id,
    wait_for_completion: true,
    timeout: 30_000
  })

done.status
# :completed | :error
```

Registry state is managed by `Jido.AI.Streaming.Registry`.

## Failure Mode: `:stream_not_found`

Symptom:
- processing or ending a stream fails with missing stream ID

Fix:
- persist the `stream_id` from `StartStream`
- do not delete from registry before finalization
- verify the stream action sequence (`start -> process -> end`)

## Defaults You Should Know

- `auto_process` default: `true`
- `buffer` default: `false`
- terminal wait poll interval: `25ms`

## When To Use / Not Use

Use streaming when:
- users need progressive rendering
- long responses benefit from partial visibility

Avoid streaming when:
- simple, short responses dominate and operational simplicity matters more

## Next

- [Observability Basics](observability_basics.md)
- [LLM Client Boundary](../developer/llm_client_boundary.md)
- [Directives Runtime Contract](../developer/directives_runtime_contract.md)
