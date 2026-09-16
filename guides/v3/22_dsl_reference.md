# AI Agent DSL reference

The normal static form is `use Jido.AI.Agent` with an `agent` block and one or
more named `ai` profiles. Routes bind Signals to profiles. The authoring
compiler validates options before the Agent starts.

| Block or form | Purpose | Start with |
| --- | --- | --- |
| `schema` | Durable Agent state shape | A small Zoi object |
| `ai :name` | Named AI behavior | One `:assistant` profile |
| `model` / `models` | Provider model or named model choices | One model |
| `instructions` | Task direction | Short, specific text |
| `reasoning` | Model/tool sequence | Default or `:react` for tools |
| `tools` | Declared Action and Flow tools | Only required tools |
| `controls` | Time, call, stage, and steering rules | Timeout and call limits |
| `result` | Output schema, repair, and state destination | `into:` field |
| `memory` | Retained Session field | Add for multi-request Context |
| `observability` | Content and diagnostics policy | Default until needed |
| `plugin` | Agent capability or policy extension | Add for a clear use case |
| `routes` | Signal path to a profile | One AI route |

The [DSL map](04_dsl_map.md) shows these forms in one Agent. Use parentheses
only when Elixir needs them for a multi-line call, such as a structured
`result(...)`. Simple DSL lines read as `model "..."`, `timeout 10_000`, and
`result into: :reply`.

Generated `ask/3`, `ask_sync/3`, and `ask_stream/3` are the normal request
entry points. `ask` returns a handle, `ask_sync` waits, and `ask_stream`
returns a handle plus events. Request options can narrow tools, select a
model, provide trusted tool context, or change a supported ReAct limit for
that request. A request option does not rewrite the Agent definition.

Use the [DSL module documentation](../../lib/jido_ai/dsl.ex) and
[authoring tests](../../test/authoring/README.md) for exact accepted values.
Unsupported dynamic native tool sources must not appear as a working DSL
option. Keep provider clients, PIDs, and request handles out of Agent state.
