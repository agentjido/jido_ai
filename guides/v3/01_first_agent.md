# Your first AI Agent

An AI Agent is a Jido Agent with an AI profile. The Agent owns durable domain
state. The profile states which model to call, how to reason, which tools are
available, and where the answer goes. A module definition does not start a
process or call a model.

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
    route "my_app.answer", ai: :assistant do
      define :answer, args: [:query]
    end
  end
end
```

Start Jido, start one AgentServer, and use the generated AI helper:

```elixir
{:ok, _jido} = Jido.start()
{:ok, server} = Jido.start_agent(MyApp.AnswerAgent)
{:ok, answer} = MyApp.AnswerAgent.ask_sync(server, "What is Jido AI?")
```

`ask_sync/3` waits for the AI request to finish. `ask/3` returns a request
handle when the caller must do other work while the model runs. A core
`define` helper such as `answer/3` reports admission of the Signal. It is not
the model's final answer. Use the generated `ask` helpers for AI work.

The first change to make is an instruction, not a custom runtime. Keep one
profile and one route until you have a reason for more. Set a timeout and a
model-call limit so an external provider cannot make the turn unbounded.

Run [First answer](../livebooks/first_answer.livemd) without credentials. It
uses a local model server but still runs the normal AgentServer and request
path. Next, [add a tool](02_tools_and_react.md).
