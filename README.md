# Jido AI

[![CI](https://github.com/agentjido/jido_ai/actions/workflows/ci.yml/badge.svg)](https://github.com/agentjido/jido_ai/actions/workflows/ci.yml)
[![License](https://img.shields.io/hexpm/l/jido_ai.svg)](LICENSE)

Jido AI adds model calls, tool use, reasoning methods, and request control to
Jido Agents. You author one Agent with `use Jido.AI.Agent`. The AI DSL states
what it can do; Jido AgentServer and Jido Flow run the work.

This `v3-spike` branch is active V3 work, not a stable V3 release. The Hex
package can be on a different version. Use this checkout and the compatible
sibling V3 packages to run these guides and Livebooks.

## One Agent, one answer

```elixir
defmodule MyApp.AnswerAgent do
  use Jido.AI.Agent, name: "answer_agent"

  agent do
    schema Zoi.object(%{answer: Zoi.string() |> Zoi.default("")})

    ai :assistant do
      model "openai:gpt-4o-mini"
      instructions "Answer in one short sentence."

      controls do
        timeout 10_000
        max_model_calls 1
      end

      result into: :answer
    end
  end

  routes do
    route "my_app.answer", ai: :assistant
  end
end

{:ok, _jido} = Jido.start()
{:ok, server} = Jido.start_agent(MyApp.AnswerAgent)
{:ok, answer} = MyApp.AnswerAgent.ask_sync(server, "What is Jido AI?")
```

`ask_sync/3` waits for the result. `ask/3` returns a request handle for work
that can take longer. `ask_stream/3` returns a handle and events. The accepted
answer can also update the Agent's domain state through `result into:`.

The [First answer Livebook](guides/livebooks/first_answer.livemd) runs this
path with a local MockLLM server and no credential. One `backend` value
switches it to a real model. Add a tool only after this first request works.

## Learn the system

The [V3 learning path](guides/v3/learning_path.md) starts with one answer and
then adds a tool and three ReAct rounds. Written guides explain the authoring
surface, runtime sequence, controls, policy, observability, and Context. Ten
Livebooks let you inspect those behaviors. Each starts in mock mode and can
switch to live mode without changing the Agent definition.

For exact authoring forms, use the [DSL reference](guides/v3/22_dsl_reference.md).
For executable integration claims, use the [example catalog](examples/README.md).
The [design documents](docs/design/README.md) track design targets and gaps;
the code and tests are the current contract.

## Runtime boundary

`Jido.AgentServer` owns the committed Agent value. An AI request is admitted
by a short Jido Turn, then its Coordinator and Jido Flow do model and tool
work. A later Turn settles the result. `Jido.Session` and `Jido.Thread` are
portable data; Context is the selected conversation sent to the model. A
Session is not the live request worker.

Tools are declared Jido Actions or Flows. They can have external effects, so
a failed final answer cannot undo every tool action. Use schema validation,
tool access policy, time and call limits, and application idempotency where
the operation needs them. See [Anatomy of an AI turn](guides/v3/09_turn_sequence.md)
and [Tool access and effects](guides/v3/14_tool_policy.md).

## Work on this checkout

Run commands inside `jido_ai/`, not the parent folder of separate Git
repositories:

```sh
mix deps.get
mix compile
mix test
mix examples --seed 0
mix docs
```

The standard unit test alias excludes example and authoring suites; run those
separately when you change their contracts. Livebooks use sibling path
dependencies so they run against this V3 code. Real mode needs the API key
named in each notebook; mock mode needs none.

For the wider Jido package map, see [jido.run](https://jido.run).
