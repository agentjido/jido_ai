# Observability and events

`Jido.AI.Result.events` is the canonical ordered event sequence for one AI
request. `trace` contains the same list for compatibility.

Each event is a plain portable Map:

```elixir
%{
  request_id: "...",
  run_id: "...",
  sequence: 1,
  type: :request_started,
  elapsed_ms: 0,
  iteration: 0,
  data: %{}
}
```

Default ReAct events include:

- `:request_started`
- `:model_completed`
- `:tool_round_completed`
- `:request_completed`
- `:request_failed`

Sequence values start at one and increase without gaps. All events for one
result have the same request ID and run ID. There is one terminal event and no
event after it.

Event data contains summaries, identifiers, counts, tool names, timing, and
usage. It does not contain model text, hidden model reasoning, request headers,
or provider secrets.

Streams, Jido Signals, telemetry, and retained traces should be projections
from this event vocabulary. They must not define separate event order rules.
