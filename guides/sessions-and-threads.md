# Sessions and Threads

An AI Agent keeps its whole conversation in one field, `state.session`.
That field holds a `Jido.Session`, which owns one append-only
`Jido.Thread`. Both are immutable, portable values: you can encode them to
JSON, store them, move them to another node, and decode them back. This
guide covers what goes into a Thread, how revisions count, and how an Agent
commits a completed request. Read [Getting Started](getting-started.livemd)
first.

```elixir
defmodule MyApp.SupportAgent do
  use Jido.AI.Agent,
    name: "support_agent",
    id: "my_app/support_agent",
    vsn: 1

  ai do
    reasoning Jido.AI.Reasoning.ReAct
  end
end

# Offline model: one OpenAI Responses API answer.
Req.Test.stub(MyApp.LLM, fn conn ->
  Req.Test.json(conn, %{
    "id" => "resp-1",
    "object" => "response",
    "created_at" => 1,
    "model" => "gpt-4o-mini-2024-07-18",
    "status" => "completed",
    "output" => [
      %{
        "type" => "message",
        "id" => "msg-1",
        "role" => "assistant",
        "status" => "completed",
        "content" => [%{"type" => "output_text", "text" => "It shipped.", "annotations" => []}]
      }
    ],
    "usage" => %{"input_tokens" => 30, "output_tokens" => 3, "total_tokens" => 33}
  })
end)

offline = %{
  api_key: "offline-test-key",
  max_retries: 0,
  req_http_options: [plug: {Req.Test, MyApp.LLM}]
}

agent = MyApp.SupportAgent.instantiate!(id: "support-1")
agent.state.session
# => nil

signal = MyApp.SupportAgent.request_signal!(%{input: "Where is order A-1001?", options: offline})
{:ok, agent, _directives} = MyApp.SupportAgent.cmd(agent, signal)

session = agent.state.session
{session.id, session.rev, session.thread.id}
# => {"session:support-1", 4, "session:support-1:thread"}

Enum.map(session.thread.entries, &{&1.seq, &1.kind, &1.payload["role"]})
# => [
#      {0, :ai_message, "user"},
#      {1, :ai_model_attempt, nil},
#      {2, :ai_message, "assistant"},
#      {3, :ai_request_outcome, nil}
#    ]
```

One request added four entries: the user message, a record of the model
call, the assistant message, and the request outcome.

## Session and Thread

| | `Jido.Session` | `Jido.Thread` |
| --- | --- | --- |
| Holds | One Thread, `status`, `metadata` | Ordered `entries`, `metadata` |
| Changes | `append/2`, `put_metadata/2`, `close/1` | `append/2` only |
| `rev` | Thread appends plus Session changes | Equals the entry count |
| Encoded `type` | `"jido.session"` | `"jido.thread"` |
| Created by the Agent | `"session:" <> agent_id` on the first request | `session.id <> ":thread"` |

Neither value owns a process or a storage adapter. The Agent owns the
Session as state, and `Jido.AgentServer` owns persistence and the commit.
Every function returns a new value; the input is unchanged.

```elixir
session = Jido.Session.new(id: "session:support-1", now: 1_000)
{session.rev, session.status, session.thread.id}
# => {0, :open, "session:support-1:thread"}
```

Use `Jido.Session.new/1` options `:id`, `:now`, `:thread`, and
`:metadata`, or `Jido.Session.from_thread/2` to wrap a Thread you already
have.

## Entries

Each `Jido.Thread.Entry` has six fields:

| Field | Contents |
| --- | --- |
| `id` | Unique ID, `"entry_..."` by default. |
| `seq` | Position in the Thread, from 0. The Thread assigns it on append. |
| `at` | Millisecond timestamp. Defaults to the append time. |
| `kind` | A non-nil atom or a non-empty string. Defaults to `:note`. |
| `payload` | The entry data. A map. |
| `refs` | Correlation IDs, such as `request_id` and `run_id`. A map. |

`Jido.Thread.append/2` accepts one entry, a map, or a list. A list appends
in order and adds one revision per entry:

```elixir
thread =
  Jido.Thread.new(id: "thread-1")
  |> Jido.Thread.append([
    %{kind: "support.ticket_opened", payload: %{ticket_id: "T-42"}},
    %{kind: :note, payload: %{text: "Customer prefers email."}}
  ])

{thread.rev, Enum.map(thread.entries, &{&1.seq, &1.kind})}
# => {2, [{0, "support.ticket_opened"}, {1, :note}]}
```

Read entries with `Jido.Thread.to_list/1`, `Jido.Thread.last/1`,
`Jido.Thread.get_entry/2`, `Jido.Thread.slice/3`, and
`Jido.Thread.filter_by_kind/2`.

## Observations

A Thread has two kinds of entry. Messages are what the model said and saw.
Observations are everything else the runtime recorded. Use
`Jido.AI.Thread.Projection` to write both, so payloads stay in the format
the projection reads back:

| Function | Writes | Model sees it |
| --- | --- | --- |
| `Projection.append/4` | One `:ai_message` entry from a `ReqLLM.Message` or a message map | If eligible |
| `Projection.observe/5` | One entry of any atom kind, with a JSON-normalized payload | Never |

The AI Agent runtime writes these kinds:

| Kind | Written when | Payload |
| --- | --- | --- |
| `:ai_message` | User input, accepted assistant output, each tool result | `role`, `content`, `tool_calls`, `tool_call_id`, `name`, `output`, `metadata` |
| `:ai_model_attempt` | After every model call, success or failure | Status, model, usage, prompt cache facts, Context snapshots |
| `:ai_tool_attempt` | After every tool execution | Tool call ID and name, input, status, bounded output, timing |
| `:ai_review` | When a tool review is requested and resolved | Review ID, status, tool calls |
| `:ai_request_outcome` | Once, at the end of every request | Status, output, counts, usage, budget |

Every entry the runtime writes has `refs: %{request_id: ..., run_id: ...}`.
`request_id` is the request Signal ID. `run_id` is unique per request.
Tool attempts and tool results add `tool_call_id`.

The projection uses these refs as sources. An `:ai_request_outcome` whose
`status` isn't `:completed` removes every message with that `run_id` from
later prompts. A failed or blocked request stays in the Thread for audit
but never reaches the model again. Each projected `ReqLLM.Message` carries
its source entry at `metadata.jido.source`. See
[Project a Thread](project-a-thread.livemd).

You can append your own entries. Use a string kind, or an atom your
application defines, and keep the payload portable:

```elixir
session = Jido.AI.Thread.Projection.observe(session, :support_escalation, %{tier: 2}, %{ticket_id: "T-42"})
List.last(session.thread.entries).payload
# => %{"tier" => 2}
```

`observe/5` normalizes the payload through JSON, so atom keys become
strings.

## Revisions

Revisions count changes:

- `thread.rev` always equals the number of entries.
- `Session.append/2` adds the number of new entries to `session.rev`.
- `Session.put_metadata/2` and `Session.close/1` add 1 to `session.rev`
  and leave `thread.rev` alone.

So `session.rev >= session.thread.rev` always holds. Validation rejects a
value that breaks either rule.

```elixir
session = Jido.Session.new(id: "session:support-2", now: 1_000)
{:ok, session} = Jido.AI.Thread.Projection.append(session, %{role: :user, content: "Hi"})
session = Jido.Session.put_metadata(session, %{tenant: "acme"})

{session.rev, session.thread.rev}
# => {2, 1}
```

A closed Session stays readable. `Jido.Session.append/2` on it raises
`ArgumentError` with `"cannot append to a closed session"`.

## How an Agent Commits

A request never edits committed state in place. The reasoning Flow works on
a copy and returns a complete next state at the end:

1. The first step reads `state.session`, or creates
   `Jido.Session.new(id: "session:" <> agent_id)` when it's `nil`. It
   appends the user message.
2. The Flow carries the Session as an encoded map between steps. Model
   rounds append `:ai_model_attempt` entries and accepted assistant
   messages. Tool rounds append `:ai_tool_attempt` entries and tool
   results.
3. The final step appends one `:ai_request_outcome` entry and returns
   `%{state: %{session: session}, response: ...}`.
4. Jido validates the state against the Agent schema. `cmd/3` returns it
   as a candidate. `Jido.AgentServer` commits it, saves it if the Agent is
   durable, and then replies.

Steps 1 to 3 run for every request that reaches the Flow, including
failed, blocked, and budget-stopped requests. Their entries commit with
the outcome, so the Thread records what happened, and the projection
keeps them out of the next prompt. The reply's `thread_rev` matches the
committed `session.thread.rev`.

Two requests on the same Agent build one Thread. The second prompt
contains the first exchange:

```elixir
signal = MyApp.SupportAgent.request_signal!(%{input: "When will it arrive?", options: offline})
{:ok, agent, _directives} = MyApp.SupportAgent.cmd(agent, signal)

agent.state.session.rev
# => 8
```

An execution host can own the Session instead. Pass a valid open Session in
trusted caller context:

```elixir
Jido.AgentServer.call(server, signal,
  context: %{jido_ai_session: selected_session}
)
```

The reply includes the portable entries added by the request in
`session_entries`. In this mode, Jido AI does not replace the Agent state
Session. The execution host must serialize requests for the selected Session
and persist the returned entries.

The AI Agent declares `state.session` with
`Jido.AI.Thread.Projection.schema/0`: a nullable Session, default `nil`,
validated strictly with no coercion. Because `Jido.AgentServer` serializes
requests, two requests never write the same Session at once. With
`cmd/3`, you own that ordering. See
[Pure or Live Execution](pure-or-live-execution.md).

## Encode and Decode

`Jido.Session.encode/1` returns a versioned map of strings, numbers,
lists, and maps. `Jido.Session.decode/1` validates it:

```elixir
json = session |> Jido.Session.encode() |> Jason.encode!()
{:ok, restored} = json |> Jason.decode!() |> Jido.Session.decode()

{restored.id, restored.rev, restored.thread.rev}
# => {"session:support-2", 2, 1}
```

| Input | Result |
| --- | --- |
| A valid map or `%Jido.Session{}` | `{:ok, session}` |
| `type` isn't `"jido.session"`, or `version` isn't `1` | `{:error, :unsupported_version}` |
| Unknown keys, a broken revision, or an invalid entry | `{:error, :invalid_session}` |

`Jido.Thread.decode/1` works the same way with `:invalid_thread`.
`Jido.Session.decode!/1` raises `ArgumentError` instead.

Entry kinds encode as `%{"type" => "atom", "value" => "ai_message"}` or
`%{"type" => "string", "value" => ...}`. Decoding never creates an atom:
an atom kind that doesn't exist in the reading node makes the entry
invalid. Load the module that defines your custom atom kinds before you
decode, or use string kinds. After a JSON round trip, map keys in
`payload` and `refs` are strings.

## What Is Never Stored

Session metadata, Thread metadata, entry payloads, and entry refs must be
portable terms. Validation rejects PIDs, references, ports, functions,
improper lists, and bitstrings that aren't binaries:

```elixir
Jido.Thread.append(Jido.Thread.new(), %{kind: :note, payload: %{owner: self()}})
# ** (ArgumentError) invalid thread entry
```

The runtime keeps these out of the Session:

| Never stored | Where it lives instead |
| --- | --- |
| Processes, tasks, and monitors | The running Flow or `Jido.AgentServer` |
| Streams and stream callbacks | The model call. Chunks go out as Signals. See [Stream Model Output](stream-model-output.livemd). |
| Provider clients and credentials | ReqLLM request options. Snapshots replace `api_key` and similar keys with `"[REDACTED]"`. |
| The `Jido.AI.Context` value | `:ai_model_attempt` entries store JSON snapshots with `content: :none`. See [Context Lifecycle](context-lifecycle.md). |
| Tool callbacks and Action modules | The Agent definition and `Jido.AI.ToolSource` |

Message content is stored. Tool results enter the Thread already bounded
by the ReAct `limits.tool_output_bytes` input, 16,384 bytes by default.
See [Tool Execution and Results](tool-execution-and-results.md).

## Next

- [Project a Thread](project-a-thread.livemd) selects which messages reach
  the model.
- [Inspect Model Context](inspect-model-context.livemd) reads the
  snapshots inside `:ai_model_attempt` entries.
- [Security and Portability](security-and-portability.md) covers redaction
  and portable data rules.
