# Standalone ReAct Runtime

You want to run `Jido.AI.Reasoning.ReAct` directly — streaming events, checkpointing mid-run, and resuming later — without wrapping everything in a `Jido.AI.Agent`.

After this guide, you can use `run/3`, `stream/3`, `start/3`, `continue/3`, `collect/3`, and `cancel/3` to build checkpoint-aware ReAct workflows outside of the agent macro.

## Prerequisites

- A configured LLM provider (API key set, model resolvable via `Jido.AI.resolve_model/1`)
- At least one `Jido.Action` module to use as a tool
- A token secret configured for checkpoint persistence (see [Configuration](#configuration-via-config))

## When To Use / Not Use

| Approach | Use It For | Avoid It For |
|---|---|---|
| `Jido.AI.Agent` | Long-lived agent processes, per-request correlation, `ask/await` lifecycle | One-off scripts, stateless HTTP handlers |
| `Jido.AI.Reasoning.ReAct` (this guide) | Streaming pipelines, checkpoint/resume across processes or nodes, custom orchestration | Simple single-turn completions with no tools |
| `CallWithTools` | Deterministic one-shot or auto-execute tool loops without reasoning trace | Multi-iteration reasoning with checkpoint persistence |

Use the standalone runtime when you need direct control over the event stream, want to persist checkpoint tokens to external storage, or are building your own orchestration layer on top of ReAct.

## Build The Tool

```elixir
defmodule MyApp.Actions.AddNumbers do
  use Jido.Action,
    name: "add_numbers",
    schema: Zoi.object(%{a: Zoi.integer(), b: Zoi.integer()})

  @impl true
  def run(%{a: a, b: b}, _context), do: {:ok, %{sum: a + b}}
end
```

## Configuration Via Config

All runtime functions accept a config as a map, keyword list, or `Jido.AI.Reasoning.ReAct.Config` struct. `build_config/1` normalizes any of these into a `Config` struct.

```elixir
config = Jido.AI.Reasoning.ReAct.build_config(%{
  model: :fast,
  system_prompt: "Solve accurately. Use tools for arithmetic.",
  tools: [MyApp.Actions.AddNumbers],
  max_iterations: 10,
  streaming: true,

  # LLM options
  max_tokens: 1_024,
  temperature: 0.2,
  tool_choice: :auto,
  llm_opts: [thinking: %{type: :enabled, budget_tokens: 2048}, reasoning_effort: :high],
  req_http_options: [receive_timeout: 60_000],

  # Tool execution
  tool_timeout_ms: 15_000,
  tool_max_retries: 1,
  tool_retry_backoff_ms: 200,
  tool_concurrency: 4,
  effect_policy: %{
    mode: :allow_list,
    allow: [Jido.Agent.StateOp.SetState, Jido.Agent.Directive.Emit]
  },

  # Observability
  emit_signals?: true,
  emit_telemetry?: true,
  redact_tool_args?: true,

  # Trace capture
  capture_deltas?: true,
  capture_thinking?: true,
  capture_messages?: true,

  # Checkpoint tokens
  token_secret: "my-32-byte-minimum-secret-here!!", # required for cross-process resume
  token_ttl_ms: 600_000, # 10 minutes; nil = no expiry
  token_compress?: false
})
```

You can also set the token secret globally:

```elixir
# config/runtime.exs
config :jido_ai, :react_token_secret, System.fetch_env!("REACT_TOKEN_SECRET")
```

## Parallel Tool Ordering

ReAct may execute tool calls concurrently (`tool_concurrency > 1`), but runtime output remains deterministic:

- `:tool_completed` events are emitted in the original LLM tool-call order
- tool result messages appended to thread context preserve that same order

This means completion timing differences between tools do not reorder the observable runtime contract.

## Run To Completion

`run/3` streams internally and returns the aggregated result map. Simplest path when you do not need the event stream.

```elixir
alias Jido.AI.Reasoning.ReAct

config = %{
  model: :fast,
  system_prompt: "Solve accurately. Use tools for arithmetic.",
  tools: [MyApp.Actions.AddNumbers],
  token_secret: "my-32-byte-minimum-secret-here!!"
}

result = ReAct.run("What is 19 + 23?", config)

# result =>
# %{
#   result: "19 + 23 = 42",
#   termination_reason: :final_answer,
#   usage: %{input_tokens: 120, output_tokens: 45},
#   final_token: "rt1.eyJhbGci...",
#   trace: [%Jido.AI.Reasoning.ReAct.Event{...}, ...]
# }
```

## Streaming

`stream/3` returns a lazy `Enumerable` of `Jido.AI.Reasoning.ReAct.Event` structs. Process events as they arrive, then reduce the stream with `collect_stream/1` if you need the terminal result.

```elixir
alias Jido.AI.Reasoning.ReAct

events = ReAct.stream("What is 19 + 23?", config)

# Process events lazily
events
|> Stream.each(fn event ->
  IO.puts("[#{event.kind}] iteration=#{event.iteration} #{inspect(event.data)}")
end)
|> Stream.run()

# Or collect into a result map
result = ReAct.stream("What is 19 + 23?", config) |> ReAct.collect_stream()
```

## Start + Collect With Checkpoint Tokens

`start/3` returns run metadata and a stream handle. Consume the stream to drive execution, then extract the checkpoint token from the result.

```elixir
alias Jido.AI.Reasoning.ReAct

{:ok, handle} = ReAct.start("What is 19 + 23?", config)

# handle =>
# %{
#   run_id: "run_abc123",
#   request_id: "req_def456",
#   events: #Stream<...>,
#   checkpoint_token: nil
# }

# Drive the stream to completion and collect
result = ReAct.collect_stream(handle.events)

# result.final_token contains the checkpoint token (if the runtime emitted one)
```

## Checkpoint + Resume Flow

Persist a checkpoint token to your database or cache, then resume the run later — even in a different process or on a different node.

```elixir
alias Jido.AI.Reasoning.ReAct

# 1. Start and collect to get a checkpoint token
{:ok, handle} = ReAct.start("What is 19 + 23?", config)
result = ReAct.collect_stream(handle.events)
token = result.final_token

# 2. Persist the token (your storage layer)
MyApp.Repo.insert!(%MyApp.Checkpoint{token: token, run_id: handle.run_id})

# 3. Later: resume from the token
#    Config MUST match the original (same model, tools, system_prompt) —
#    the token includes a config fingerprint that is verified on decode.
{:ok, resumed} = ReAct.continue(token, config)
resumed_result = ReAct.collect_stream(resumed.events)

# Or use collect/3 which handles continue + collect in one call
{:ok, collected} = ReAct.collect(token, config, run_until_terminal?: true)
```

### Inspect Without Resuming

Pass `run_until_terminal?: false` to `collect/3` to decode the token and read state without running the LLM again:

```elixir
{:ok, snapshot} = ReAct.collect(token, config, run_until_terminal?: false)
# snapshot.result, snapshot.termination_reason, snapshot.token_payload
```

## Cancel A Run

`cancel/3` marks a checkpoint token as cancelled and returns a new replacement token. The cancelled token cannot be resumed.

```elixir
alias Jido.AI.Reasoning.ReAct

{:ok, cancelled_token} = ReAct.cancel(token, config)
# Default reason: :cancelled

{:ok, cancelled_token} = ReAct.cancel(token, config, :user_aborted)
```

Attempting to `continue/3` a cancelled token will restore a state with `status: :cancelled` — the runner will not produce new LLM calls.

## Event Stream Item Shapes

Every event is a `Jido.AI.Reasoning.ReAct.Event` struct:

```elixir
%Jido.AI.Reasoning.ReAct.Event{
  id: "evt_abc123",
  seq: 1,
  at_ms: 1740268800000,
  run_id: "run_abc123",
  request_id: "req_def456",
  iteration: 1,
  kind: :llm_completed,        # see kinds below
  llm_call_id: "call_xyz",     # present for LLM events
  tool_call_id: nil,           # present for tool events
  tool_name: nil,              # present for tool events
  data: %{...}                 # kind-specific payload
}
```

### Event Kinds

| Kind | Emitted When | Notable `data` Fields |
|---|---|---|
| `:request_started` | Run begins | — |
| `:llm_started` | LLM call dispatched | — |
| `:llm_delta` | Streaming token received | delta content |
| `:llm_completed` | LLM call finished | result, usage |
| `:tool_started` | Tool execution begins | tool args |
| `:tool_completed` | Tool execution finished | tool result |
| `:checkpoint` | Checkpoint token issued | `%{token: "rt1..."}` |
| `:request_completed` | Run finished successfully | `%{result: ..., termination_reason: ..., usage: ...}` |
| `:request_failed` | Run failed | `%{error: ...}` |
| `:request_cancelled` | Run was cancelled | — |

`collect_stream/1` reduces the full event list into:

```elixir
%{
  result: "...",
  termination_reason: :final_answer | :failed | :cancelled,
  usage: %{input_tokens: ..., output_tokens: ...},
  final_token: "rt1...",
  trace: [%Event{}, ...]
}
```

## Defaults You Should Know

- `model` default: `:fast`
- `max_iterations` default: `10`
- `streaming` default: `true`
- `max_tokens` default: `1_024`
- `temperature` default: `0.2`
- `tool_choice` default: `:auto`
- `llm_opts` default: `[]`
- `req_http_options` default: `[]`
- `tool_timeout_ms` default: `15_000`
- `tool_max_retries` default: `1`
- `tool_retry_backoff_ms` default: `200`
- `tool_concurrency` default: `4`
- `token_ttl_ms` default: `nil` (no expiry)
- `token_compress?` default: `false`
- Observability flags (`emit_signals?`, `emit_telemetry?`, `redact_tool_args?`) default: `true`
- Trace flags (`capture_deltas?`, `capture_thinking?`, `capture_messages?`) default: `true`

## Failure Mode: Config Fingerprint Mismatch On Resume

Symptom:
- `continue/3` or `collect/3` returns `{:error, :token_config_mismatch}`

Fix:
- The config you pass to `continue/3` must match the config used when the token was issued. The token encodes a SHA-256 fingerprint of model, system prompt, max iterations, streaming flag, tool execution settings, and tool names.
- Verify you are passing the same `model`, `system_prompt`, `tools`, `max_iterations`, `streaming`, and `tool_exec` settings.

## Failure Mode: Token Expired

Symptom:
- `continue/3` returns `{:error, :token_expired}`

Fix:
- Increase `token_ttl_ms` or set to `nil` for no expiry.
- Resume sooner after the checkpoint is issued.

## Failure Mode: Ephemeral Token Secret Warning

Symptom:
- Logger warning: "using ephemeral token secret... checkpoint tokens expire on VM restart"

Fix:
- Set a persistent secret in your config:

```elixir
# config/runtime.exs
config :jido_ai, :react_token_secret, System.fetch_env!("REACT_TOKEN_SECRET")
```

- Or pass `token_secret` explicitly in the config map.

## Failure Mode: Insecure Token Secret Rejected

Symptom:
- `ArgumentError`: "insecure ReAct token secret rejected"

Fix:
- You are using the legacy default secret. Replace it with a real secret (at least 32 bytes recommended).

## Next

- [First Agent](first_react_agent.md)
- [Tool Calling With Actions](tool_calling_with_actions.md)
- [Request Lifecycle And Concurrency](request_lifecycle_and_concurrency.md)
- [Strategy Selection Playbook](strategy_selection_playbook.md)
