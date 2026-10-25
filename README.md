# Jido AI

[![CI](https://github.com/agentjido/jido_ai/actions/workflows/ci.yml/badge.svg)](https://github.com/agentjido/jido_ai/actions/workflows/ci.yml)
[![License](https://img.shields.io/hexpm/l/jido_ai.svg)](LICENSE)

Jido AI adds model calls, tool use, reasoning Flows, and AI request controls to
Jido Agents. Core Jido owns Agent state, processes, commits, and directives.
Jido AI owns model preparation, model tools, AI limits, AI results, and AI
events.

This branch is active V3 work. Use it with the compatible sibling V3 packages
in this folder.

## One Agent and one answer

```elixir
defmodule MyApp.AnswerAgent do
  use Jido.AI.Agent, name: "answer_agent"

  ai do
    model "openai:gpt-4o-mini"
    instructions "Answer in one short sentence."

    controls do
      timeout 10_000
      max_model_calls 1
    end
  end
end

{:ok, answer} = MyApp.AnswerAgent.generate("What is Jido AI?")
```

`generate/2` returns only the accepted output. `reason/2` returns a completed
`Jido.AI.Result` with usage and events.

## Prepare before execution

`preflight/2` resolves a request without running a control, tool, or model:

```elixir
{:ok, request} =
  MyApp.AnswerAgent.preflight("What is Jido AI?",
    request_id: "request-1",
    run_id: "run-1"
  )

request.model
Jido.AI.Request.messages(request)
Jido.AI.Request.visible_tool_names(request)
request.controls
```

Execution uses the same prepared request value. There is not a separate prompt
path for inspection.

## Select tools for one request

An Agent declares its complete tool set. A caller can reduce that set for one
request:

```elixir
defmodule MyApp.ToolAgent do
  use Jido.AI.Agent, name: "tool_agent"

  ai do
    model "openai:gpt-4o-mini"

    tools do
      action MyApp.Search, as: :search
      action MyApp.Update, as: :update
    end
  end
end

{:ok, result} =
  MyApp.ToolAgent.reason("Find the account", visible_tools: [:search])
```

Hidden tools are not sent to the model. A forged call to a hidden or
undeclared tool is rejected before execution. A request cannot add a tool that
the Agent did not declare.

## Explicit results and events

`run/2` makes success and failure explicit:

```elixir
case MyApp.AnswerAgent.run("What is Jido AI?") do
  {:ok, %Jido.AI.Result{status: :completed} = result} ->
    result.output

  {:error, %Jido.AI.Result{status: status} = result} ->
    {status, result.error}

  {:error, preparation_error} ->
    preparation_error
end
```

Every request event has:

- `request_id`
- `run_id`
- `sequence`
- `type`
- `elapsed_ms`
- `iteration`
- a safe `data` Map

The final event is one of `:request_completed`, `:request_failed`, or
`:request_cancelled`. `trace` is a compatibility alias for `events`.

## Session, Thread, and model context

`Jido.Session` and `Jido.Thread` are immutable source values. They are not
model Context values and they do not own a process.

Use the core Agent initializer for fresh instance data:

```elixir
defmodule MyApp.ChatAgent do
  use Jido.AI.Agent, name: "chat_agent"

  state do
    schema Zoi.object(%{session: Jido.Session.schema()})
  end

  @impl Jido.Agent
  def initialize(state, _context) do
    {:ok, Map.put_new_lazy(state, :session, &Jido.Session.new!/0)}
  end

  ai do
    model "openai:gpt-4o-mini"
  end
end
```

Core Jido merges declared `initial_state` with explicit caller `state:` before
it calls `initialize/2`. The callback above keeps a supplied Session and creates
one only when the candidate state does not contain one.

`Jido.AI.Context.project/3` uses an Agent route reference such as
`{MyApp.ChatAgent, "chat.ask"}`. It selects complete correlated request and
reply pairs and builds a ReqLLM Context. Unrelated and incomplete Signals do
not enter the model request. Projection does not change Session or Thread data.

## State commit rule

A direct AI request does not change Agent state. Its result has
`commit: :not_requested`.

A routed turn can pass a completed result to `Jido.AI.Turn.complete/4`. This
function validates the route reply data and returns `%{state: state, reply:
reply}` for the route projections. It does not commit or build the delivered
reply by itself. Core Jido validates the complete Action output, commits the
selected state, and then delivers the correlated route reply. A provider
failure, output control failure, invalid output, or incomplete result does not
produce candidate turn state.

Jido AI cannot undo an external effect that a tool already completed. Use
application authorization and idempotency for effectful tools.

## Learn and verify

Use the [example catalog](examples/README.md). Start with:

- [Basic Agent](examples/01_basics/01_01_basic_agent/README.md)
- [Action and Flow tools](examples/01_basics/01_02_tool_flow/README.md)
- [Request contract](examples/01_basics/01_06_request_contract/README.md)
- [Conversations](examples/02_conversations/README.md)

Run commands inside `jido_ai/`:

```sh
mix deps.get
mix format --check-formatted
mix compile --warnings-as-errors
mix test --include authoring --include example --warnings-as-errors --seed 0
mix test.live
```

Live tests need the provider credentials used by ReqLLM. They write sanitized
local traces under `tmp/jido_ai_traces/`.

For the wider package map, see [jido.run](https://jido.run).
