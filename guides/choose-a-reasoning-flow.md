# Choose a Reasoning Flow

Your Agent's root Flow decides how many model calls a request can spend,
whether the model can call tools, and what lands in `reply.data.reasoning`.
This guide compares the eight built-in Flows and the inline option, so you can
pick one and change it later with one line. Read
[Core Concepts](core-concepts.md) first.

```elixir
ai do
  reasoning Jido.AI.Reasoning.ChainOfThought
end
```

## At a Glance

| Flow | Model calls | Tools | `reasoning` data |
| --- | --- | --- | --- |
| `Jido.AI.Reasoning.ReAct` | 1 to `limits.model_calls` (default 8, max 16) | Yes | `nil` |
| `Jido.AI.Reasoning.ChainOfThought` | 1 | No | `steps`, `conclusion` |
| `Jido.AI.Reasoning.ChainOfDraft` | 1 | No | `drafts`, `conclusion` |
| `Jido.AI.Reasoning.AlgorithmOfThoughts` | 1 | No | `operations`, `conclusion` |
| `Jido.AI.Reasoning.TreeOfThoughts` | 3 | No | `thoughts`, `conclusion` |
| `Jido.AI.Reasoning.GraphOfThoughts` | 2 | No | `nodes`, `edges`, `conclusion` |
| `Jido.AI.Reasoning.TRM` | 3 | No | `draft`, `critique`, `iterations`, `conclusion` |
| `Jido.AI.Reasoning.Adaptive` | The selected Flow's | Only when it selects ReAct | The selected Flow's |
| Inline or custom Flow | Yours | Yours | Yours |

Every built-in Flow returns the same response map, described in
[Core Concepts](core-concepts.md#request-and-response). `output` is the final
answer string. ReAct returns a map instead when you set `output_schema`. Every
non-ReAct `reasoning` map also has `method` (such as `:chain_of_thought`) and
`steps_count`.

## Pick One

- **The model needs data or must act:** ReAct. It's the only Flow that sends
  tools to the model.
- **One answer, with its working shown:** Chain of Thought. Chain of Draft
  keeps each step to five words or fewer. Algorithm of Thoughts asks for a
  search with backtracking and returns the operations.
- **Several candidate answers to compare:** Tree of Thoughts.
- **Many facts to relate before answering:** Graph of Thoughts.
- **A first draft that needs checking:** TRM (draft, critique, revise).
- **Mixed traffic on one Agent:** Adaptive picks one of the above per request.
- **Fixed application logic, or no model at all:** an inline or custom Flow.

For `MyApp.SupportAgent`, order questions need `lookup_order`, so it uses
ReAct. A triage Agent that only classifies tickets doesn't need tools and can
use a single-call Flow.

## Shared Input

All built-in Flows accept these request fields. Set defaults in the
`reasoning` block or override them per request:

| Field | Default |
| --- | --- |
| `input` | Required. A string, or a list of content-part maps. |
| `instructions` | A Flow-specific system prompt. Every Flow except ReAct and Adaptive returns it from `default_instructions/0`. |
| `model` | `"openai:gpt-4o-mini"` |
| `options` | ReqLLM options. Flow-specific, see below. |
| `prompt_cache` | `%{enabled: false}` |
| `context` | `%{max_messages: 64, max_bytes: 200_000}` |
| `limits` | `elapsed_ms: 120_000`; `input_tokens`, `output_tokens`, `total_tokens`, and `total_cost` are `nil` (no limit) |

Default `options` per Flow:

| Flow | `max_tokens` | `temperature` |
| --- | --- | --- |
| ReAct | 128 | 0.0 |
| Chain of Thought | 512 | 0.0 |
| Chain of Draft | 256 | 0.0 |
| Algorithm of Thoughts | 1024 | 0.0 |
| Tree of Thoughts | 1536 | 0.4 |
| Graph of Thoughts | 1536 | 0.3 |
| TRM | 1536 | 0.2 |

ReAct and Chain of Thought also set `receive_timeout: 30_000`.

A request field replaces the whole default for that field. Nested maps don't
merge. If the Agent declares `limits do model_calls 6 end` and a request sends
`limits: %{tool_rounds: 1}`, that request runs with `model_calls: 8`, the
schema default. The same holds for `options`.

Each Flow's schema rejects keys it doesn't define. Sending `tool_policy` to a
Chain of Thought Agent returns
`{:error, %Jido.Action.Error.InvalidInputError{message: "unrecognized key: tool_policy"}}`.
`explain/0` returns the selected Flow's `input_schema`.

## ReAct

ReAct loops: model call, then either a final answer or a round of tool calls,
then another model call. It adds these fields:

| Field | Default |
| --- | --- |
| `fallback_models` | `[]` |
| `stream` | `false` |
| `output_schema` | `nil`. A JSON Schema map makes `output` a validated map. |
| `review_tools` | `false` |
| `tool_policy` | All Agent tools visible; `requirement: :optional` |
| `limits.model_calls` | 8 (1 to 16) |
| `limits.tool_rounds` | 4 (0 to 8) |
| `limits.tool_calls` | 8 (1 to 16) |
| `limits.retries` | 1 (0 to 4) |
| `limits.tool_output_bytes` | 16,384 |

Retries, fallback models, and output-repair rounds all count toward
`model_calls`. When a limit stops the request, `status` is `:blocked` and
`reason_code` is `:limits`. See [ReAct](react.livemd).

## Single-Call Flows

Chain of Thought, Chain of Draft, and Algorithm of Thoughts make exactly one
model call with no retries and no fallback model. Each asks for a strict JSON
object:

| Flow | Model returns | `reasoning` |
| --- | --- | --- |
| Chain of Thought | `steps` (`number`, `content`), `conclusion` | `steps: [%{number: 1, content: "..."}]`, `conclusion` |
| Chain of Draft | `drafts` (strings), `answer` | `drafts: ["..."]`, `conclusion` |
| Algorithm of Thoughts | `operations` (strings), `answer` | `operations: ["..."]`, `conclusion` |

`output` is the conclusion. If the model returns no valid object, `status` is
`:blocked`, `reason_code` is `:output`, and the reason is
`"model output is missing required structured data"`. There's no repair
round. See [Single-Call Reasoning](single-call-reasoning.livemd).

## Multi-Stage Flows

These run fixed stages. Each stage is one structured model call:

| Flow | Stages | Calls | `reasoning` |
| --- | --- | --- | --- |
| Tree of Thoughts | Generate candidates (asks for four, at least two); score each 0 to 1; keep the top two (no model call); synthesize | 3 | `thoughts: [%{content: ..., score: ...}]` |
| Graph of Thoughts | Build nodes and edges; synthesize | 2 | `nodes: [%{id: ..., content: ...}]`, `edges: [%{from: ..., to: ..., relationship: ...}]` |
| TRM | Draft; critique; revise | 3 | `draft`, `critique`, `iterations: 1` |

Only the final answer enters the conversation as an assistant message. The
intermediate calls are recorded as `:ai_model_attempt` entries. A Graph of
Thoughts edge that names an unknown node blocks the request with
`"graph edges must reference existing node IDs"`. See
[Multi-Stage Reasoning](multi-stage-reasoning.livemd).

## Adaptive

Adaptive runs no model call of its own. It reads the request text and selects
one Flow. The first matching rule wins:

| Request text contains | Selected Flow |
| --- | --- |
| puzzle, riddle, iterate, improve, refine, recursive | TRM |
| synthesize, combine, merge, integrate, relationships, perspectives | Graph of Thoughts |
| search, find, lookup, fetch, calculate, compute, execute, run, tool | ReAct |
| algorithm, backtrack, search-space, optimize | Algorithm of Thoughts |
| analyze, explore, compare, evaluate, alternatives, options | Tree of Thoughts |
| Fewer than 12 words | Chain of Draft |
| Anything else | Chain of Thought |

Words are matched whole, so "look up" doesn't match `lookup`. Set `strategy`
to skip the heuristic, for example `strategy: :chain_of_thought`. The allowed
values are `:react`, `:chain_of_thought`, `:chain_of_draft`,
`:algorithm_of_thoughts`, `:tree_of_thoughts`, `:graph_of_thoughts`, and
`:trm`.

`reply.data.flow` names the Flow that ran:

```elixir
reply.data.flow
# => %{id: "jido.ai/reasoning/chain-of-draft", vsn: 1}
```

Adaptive has no defaults of its own; the selected Flow applies its defaults.
It passes extra fields through, so `preflight/1` accepts `tool_policy`. If the
selected Flow isn't ReAct, the request then fails with
`"unrecognized key: tool_policy"`. Send ReAct-only fields only with
`strategy: :react`. See [Adaptive Reasoning](adaptive-reasoning.livemd).

## Inline or Custom Flow

When the steps are yours, write the Flow. An inline Flow lives in the Agent:

```elixir
defmodule MyApp.FaqAgent do
  use Jido.AI.Agent, id: "my_app/faq_agent", vsn: 1, name: "faq_agent"

  ai do
    reasoning do
      step "answer", question <- input(:input), inline: [context: context] do
        answer =
          if String.contains?(String.downcase(question), "refund"),
            do: "Refunds post within 5 business days.",
            else: "A support specialist will reply shortly."

        {:ok, %{state: context.agent_state, response: %{status: :completed, output: answer}}}
      end

      output result("answer")
    end
  end
end

agent = MyApp.FaqAgent.instantiate!(id: "faq-1")
signal = MyApp.FaqAgent.request_signal!(%{input: "When will my refund arrive?"})

{:ok, next_agent, [%Jido.Agent.Directive.Reply{signal: reply}]} =
  MyApp.FaqAgent.cmd(agent, signal)

{reply.data, next_agent.state}
# => {%{status: :completed, output: "Refunds post within 5 business days."}, %{session: nil}}
```

The Flow's output must be `%{state: map(), response: map()}`. `state` becomes
the next Agent state, and `response` is the reply data, unchanged. The built-in
contract (Session updates, limits, guards, usage) applies only if your Flow
provides it.

A custom `Jido.Flow` module works the same way and adds a schema. Its Zoi input
schema becomes the request schema and the set of fields the `reasoning` block
accepts. [Agent Authoring](agent-authoring.md) covers both forms.
