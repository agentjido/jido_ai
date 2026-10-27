# Jido AI

[![CI](https://github.com/agentjido/jido_ai/actions/workflows/ci.yml/badge.svg)](https://github.com/agentjido/jido_ai/actions/workflows/ci.yml)
[![License](https://img.shields.io/hexpm/l/jido_ai.svg)](LICENSE)

Jido AI adds graph-first model reasoning and tool use to Jido Agents.

An AI Agent has one root reasoning Flow. The Flow makes model calls, applies
limits, selects tools, and returns normal Jido route output. Core Jido owns the
Agent process, route execution, state commit, replies, and directives. ReqLLM
owns provider and model integration.

Jido AI V3 is under active development. Use it with compatible V3 versions of
`jido`, `jido_action`, and `jido_signal`.

## Define an AI Agent

```elixir
defmodule MyApp.AnswerAgent do
  use Jido.AI.Agent,
    id: "my_app/answer_agent",
    vsn: 1,
    name: "answer_agent"

  ai do
    reasoning Jido.AI.Reasoning.ReAct do
      model "openai:gpt-4o-mini"
      instructions "Answer in one short sentence."

      limits do
        model_calls 1
        tool_rounds 0
      end
    end
  end
end
```

The selected reasoning Flow owns the request schema and defaults. ReAct is the
general tool-using Flow. An Agent can select another `Jido.Flow` module or
define a small Flow inline.

Inspect the Agent without model execution:

```elixir
MyApp.AnswerAgent.reasoning()
#=> Jido.AI.Reasoning.ReAct

MyApp.AnswerAgent.explain()

{:ok, preflight} =
  MyApp.AnswerAgent.preflight(%{input: "What is Jido AI?"})

preflight.params
preflight.workflow
```

`preflight/1` validates the request and compiles the root Flow. It does not
call a model or build the final model Context.

## Run one request

ReqLLM reads the provider credentials for the selected model.

```elixir
agent = MyApp.AnswerAgent.instantiate!(id: "answer-1")
signal = MyApp.AnswerAgent.request_signal!(%{input: "What is Jido AI?"})

{:ok, next_agent, [%Jido.Agent.Directive.Reply{signal: reply}]} =
  MyApp.AnswerAgent.cmd(agent, signal)

reply.data.status
reply.data.output
reply.data.usage
next_agent.state.session
```

Use `Jido.AgentServer` when the Agent needs a live process, persistence,
waiting, or committed state across requests.

## Add tools

Static tools are Jido Actions or Flows. The Agent declaration is the protected static
tool list.

```elixir
defmodule MyApp.Add do
  use Jido.Action,
    id: "my_app/actions/add",
    vsn: 1,
    name: "add",
    description: "Add two numbers.",
    schema: Zoi.object(%{left: Zoi.number(), right: Zoi.number()}),
    output_schema: Zoi.object(%{value: Zoi.number()})

  @impl Jido.Action
  def run(%{left: left, right: right}, _context) do
    {:ok, %{value: left + right}}
  end
end

defmodule MyApp.ToolAgent do
  use Jido.AI.Agent,
    id: "my_app/tool_agent",
    vsn: 1,
    name: "tool_agent"

  ai do
    reasoning Jido.AI.Reasoning.ReAct

    tools do
      action MyApp.Add
    end
  end
end
```

Select a smaller tool set for one request with semantic policy:

```elixir
MyApp.ToolAgent.request_signal!(%{
  input: "Add 2 and 3.",
  tool_policy: %{
    visible: ["add"],
    requirement: :required,
    reason: "This request requires arithmetic."
  }
})
```

Raw provider `tools:` options must not replace the Agent allowlist. Application
authorization and idempotency are still required for tools with external
effects. Trusted execution hosts can add dynamic tools with
`Jido.AI.ToolSource`; request data cannot add tool sources.

## Session, Thread, and projection

`Jido.Session` owns one portable `Jido.Thread`. The Thread is the durable
conversation source. It can contain model messages, model attempts, reviews,
request outcomes, and other observations.

`Jido.AI.Thread.Projection` selects the messages that can enter a model call:

```elixir
{:ok, projection} =
  Jido.AI.Thread.Projection.context(session, %{
    max_messages: 64,
    max_bytes: 200_000
  })

projection.context
#=> %ReqLLM.Context{}

projection.decisions
```

Projection excludes failed request messages and incomplete tool exchanges. It
does not change the Session or Thread.

## Inspect one model Context

`Jido.AI.Context` is the graph-independent lifecycle boundary for one ReqLLM
call. It wraps the exact `ReqLLM.Context`, model, options, and result.

```elixir
req_context =
  ReqLLM.Context.new([
    ReqLLM.Context.user("Use the known customer details.")
  ])

{:ok, context} = Jido.AI.Context.new(req_context)

{:ok, context} =
  Jido.AI.Context.transform(context, "customer-memory:42:v1", fn req_context ->
    memory =
      ReqLLM.Context.system("The customer name is Ada.",
        metadata: %{source: "customer-memory", record_id: "42"}
      )

    %{req_context | messages: [memory | req_context.messages]}
  end)

{:ok, context} =
  Jido.AI.Context.prepare(context,
    model: "openai:gpt-4o-mini",
    options: [temperature: 0]
  )

before_call = Jido.AI.Context.snapshot(context, content: :none)

result =
  ReqLLM.generate_text(
    context.request.model,
    context.request.context,
    context.request.options
  )

{:ok, context} = Jido.AI.Context.complete(context, result)
after_call = Jido.AI.Context.snapshot(context, content: :none)

Jido.AI.Context.diff(before_call, after_call)
```

Context transformations are generic and idempotent by operation ID. Memory,
skills, retrieval, and other plugins can use this boundary without adding
domain-specific methods to Context.

Snapshots expose request and response shape, message and tool counts, stable
digests, operations, token usage, cache facts, provider metadata, and response
context. Snapshot content modes are `:none`, `:redacted`, and `:full`. The
default is `:redacted`.

Normal Jido AI reasoning Flows use this Context lifecycle automatically and
store content-free before-and-after snapshots with each model attempt.

## Reasoning Flows

Jido AI includes these graph-first reasoning Flows:

- `Jido.AI.Reasoning.ReAct`
- `Jido.AI.Reasoning.ChainOfThought`
- `Jido.AI.Reasoning.ChainOfDraft`
- `Jido.AI.Reasoning.AlgorithmOfThoughts`
- `Jido.AI.Reasoning.TreeOfThoughts`
- `Jido.AI.Reasoning.GraphOfThoughts`
- `Jido.AI.Reasoning.TRM`
- `Jido.AI.Reasoning.Adaptive`

Each Flow has its own Zoi input schema. Use the Flow schema as the source of
truth for supported defaults and request fields.

## Test and verify

Offline tests mock ReqLLM directly. They do not need provider credentials.

```sh
mix deps.get
mix format --check-formatted
mix compile --force --warnings-as-errors
mix test --warnings-as-errors --seed 0
```

Run live provider tests separately:

```sh
mix test.live
```

Live tests need the provider credentials used by ReqLLM. Sanitized local test
evidence can be written under `tmp/jido_ai_traces/`.

For the wider package map, see [jido.run](https://jido.run).
