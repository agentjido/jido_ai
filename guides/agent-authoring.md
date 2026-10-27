# Agent Authoring

This guide covers the authoring choices past the basic `ai` block: writing
the root reasoning Flow inline or as its own module, checking a definition
before it serves traffic, storing it as JSON, and adding core Agent features
such as Plugins. Read [Define an AI Agent](define-an-ai-agent.livemd) first;
the examples reuse its `MyApp.SupportAgent`, `MyApp.LookupOrder`, and
`MyApp.IssueRefund`.

## What A Definition Holds

`use Jido.AI.Agent` produces a normal `Jido.Agent` definition. The `ai` block
lowers to one extension entry, and that entry derives one route:

| Part | Value |
| --- | --- |
| State schema | `session` (a `Jido.Session` or `nil`), plus Plugin-owned fields |
| Extension `jido.ai/agent` | `%{reasoning: flow_module, defaults: map, tools: [action_module]}` |
| Derived route | `jido.ai.request` → the reasoning Flow → reply `jido.ai.response` |

The route runs the Flow directly. The Flow's output must be
`%{state: map, response: map}`: `state` becomes the next Agent state and
`response` becomes the reply data. There is no hidden pipeline around the
Flow, so whatever Flow you select owns the whole request.

## Inline Or Referenced

A referenced Flow is a module. Its input schema defines the `reasoning` block
fields:

```elixir
defmodule MyApp.Reasoning.AfterHours do
  use Jido.Flow,
    id: "my_app/reasoning/after_hours",
    vsn: 1,
    name: "after_hours",
    schema:
      Zoi.object(
        %{
          input: Zoi.string(),
          greeting: Zoi.string() |> Zoi.default("Thanks for writing"),
          reopens_at: Zoi.string() |> Zoi.default("09:00 UTC")
        },
        unrecognized_keys: :error
      ),
    output_schema: Zoi.object(%{state: Zoi.map(), response: Zoi.map()})

  flow do
    step "acknowledge",
         [greeting <- input(:greeting), reopens_at <- input(:reopens_at)],
         inline: [context: context] do
      {:ok,
       %{
         state: context.agent_state,
         response: %{output: "#{greeting}. The desk reopens at #{reopens_at}."}
       }}
    end

    output result("acknowledge")
  end
end

defmodule MyApp.AfterHoursAgent do
  use Jido.AI.Agent, id: "my_app/after_hours_agent", vsn: 1, name: "after_hours_agent"

  ai do
    reasoning MyApp.Reasoning.AfterHours do
      reopens_at "08:00 UTC"
    end
  end
end
```

```elixir
agent = MyApp.AfterHoursAgent.instantiate!(id: "after-hours-1")
signal = MyApp.AfterHoursAgent.request_signal!(%{input: "Where is order A-1001?"})
{:ok, _agent, [reply]} = MyApp.AfterHoursAgent.cmd(agent, signal)

reply.signal.data
# => %{output: "Thanks for writing. The desk reopens at 08:00 UTC."}
```

`reopens_at` and `greeting` are DSL fields because the Flow schema defines
them. `confidence 0.9` in that block fails to compile with
`Flow default field is unknown`.

An inline Flow lives in the Agent module:

```elixir
defmodule MyApp.EchoAgent do
  use Jido.AI.Agent, id: "my_app/echo_agent", vsn: 1, name: "echo_agent"

  ai do
    reasoning do
      step "echo", input <- input(:input), inline: [context: context] do
        {:ok, %{state: context.agent_state, response: %{output: "Echo: " <> input}}}
      end

      output result("echo")
    end
  end
end
```

The body uses the `Jido.Flow` language: `step`, `output`, `input/1`, and
`result/1`. Jido compiles it into a generated Flow module:

```elixir
MyApp.EchoAgent.reasoning()
# => Jido.Flow.Generated.Inline.F700d0c0...
```

| | Referenced Flow | Inline Flow |
| --- | --- | --- |
| Input schema | Yours, enforced | Any map; nothing is validated |
| `reasoning` defaults block | Yes | No |
| Reusable across Agents | Yes | No |
| Stable `id` and `vsn` for JSON | Yes | No; the module name is generated |
| Use for | Production Agents, shared recipes | Tests, prototypes, one-off Agents |

With an inline Flow, `preflight(%{})` returns `{:ok, ...}`, because the
generated schema accepts any map. Validate the input in the step, or move to
a referenced Flow when the request shape matters.

Neither Flow above calls a model or touches the Session: both return
`context.agent_state` unchanged, so `state.session` stays `nil`. The built-in
Flows, such as `Jido.AI.Reasoning.ReAct`, append to the Session and commit it
in `state`. [Choose a Reasoning Flow](choose-a-reasoning-flow.md) lists them.

## Preflight Checks

`preflight/1` runs every check that doesn't need a model:

1. Merge the Agent defaults into the request data.
2. Validate the result against the Flow input schema.
3. Validate the tool Actions and Flows.
4. Resolve the Flow and compile it into a workflow.

It doesn't check provider credentials, model names, or network access, run a
tool, or start a process. Put it in your test suite so a schema change in a
Flow or a tool fails CI, not the first live request:

```elixir
defmodule MyApp.SupportAgentTest do
  use ExUnit.Case, async: true

  test "the support Agent accepts its documented requests" do
    assert {:ok, %{params: params}} =
             MyApp.SupportAgent.preflight(%{input: "Where is order A-1001?"})

    assert params.model == "openai:gpt-4o-mini"
    assert params.limits.model_calls == 4

    assert {:error, %Jido.Action.Error.InvalidInputError{}} =
             MyApp.SupportAgent.preflight(%{input: "Hi", tools: ["delete_everything"]})
  end
end
```

The second request fails with `unrecognized key: tools`: request data can't
add tools. Use `explain/0` when you want the defaults and tool list as data,
for an admin page or a snapshot test.

## Portable Definitions

To store an Agent definition in a database, encode it with
`Jido.Authoring.encode_json/2`. The document refers to modules only by the
`{id, vsn}` keys of a Registry you build in code, so stored data can't choose
which code runs. [Documents and Views](https://hexdocs.pm/jido/agent-documents-and-views.html)
covers the Registry and codec in detail.

An AI Agent's Registry needs one entry per module the definition references:

```elixir
entries = %{
  {"my_app/support_agent", 1} => {:agent, MyApp.SupportAgent},
  {"my_app/support_agent_state", 1} => {:schema, MyApp.SupportAgent.definition().schema},
  {"jido.ai/agent", 1} => {:extension, Jido.AI.Agent.Extension},
  {"jido.ai/reasoning/react", 1} => {:flow, Jido.AI.Reasoning.ReAct},
  {"my_app/actions/lookup_order", 1} => {:action, MyApp.LookupOrder},
  {"my_app/actions/issue_refund", 1} => {:action, MyApp.IssueRefund}
}

registry = Jido.Authoring.Registry.new!(entries)
opts = [registry: registry, codec: Jido.Agent.Codec]
{:ok, json} = Jido.Authoring.encode_json(MyApp.SupportAgent, opts)
```

| Entry | Why |
| --- | --- |
| `:agent` | The Agent module. |
| `:schema` | The composed state schema, read from `definition().schema`. |
| `:extension` `"jido.ai/agent"` v1 | The AI extension that stores the `ai` block. |
| `:flow` | The reasoning Flow. Built-in Flows have stable ids such as `"jido.ai/reasoning/react"`. |
| `:action` | Every tool. |

The AI data sits in the definition's `extensions` list:

```json
{
  "id": "jido.ai/agent",
  "provider": {"id": "jido.ai/agent", "vsn": 1},
  "vsn": 1,
  "data": {
    "reasoning": {"id": "jido.ai/reasoning/react", "vsn": 1},
    "config": {
      "instructions": "You answer customer-support questions. Look up orders before you answer.",
      "model": "openai:gpt-4o-mini",
      "fallback_models": ["anthropic:claude-haiku-4-5"],
      "context": {"max_messages": 32, "max_bytes": 200000},
      "limits": {
        "model_calls": 4, "tool_rounds": 2, "tool_calls": 8, "retries": 1,
        "elapsed_ms": 120000, "tool_output_bytes": 16384,
        "input_tokens": null, "output_tokens": null, "total_tokens": null, "total_cost": null
      }
    },
    "tools": [
      {"id": "my_app/actions/lookup_order", "vsn": 1},
      {"id": "my_app/actions/issue_refund", "vsn": 1}
    ]
  }
}
```

`config` holds the `reasoning` defaults, encoded through the Flow's input
schema. The definition's `routes` list is empty: the extension derives the
`jido.ai.request` route again on import.

Decode with the same Registry, then instantiate the definition through
`Jido.Agent`:

```elixir
{:ok, definition} = Jido.Authoring.decode_json(json, opts)
definition == MyApp.SupportAgent.definition()
# => true

agent = Jido.Agent.instantiate!(definition, id: "support-from-json")
signal = Jido.Agent.input_signal!(definition, "jido.ai.request", %{input: "Where is order A-1001?"})

{agent.state, signal.type, signal.source}
# => {%{session: nil}, "jido.ai.request", "/my_app/support_agent"}
```

Run the instance with `Jido.Agent.cmd/3`, or pass it to `Jido.start_agent/2`.

Import fails closed. A document that names a tool missing from the Registry
returns one issue and no definition:

```elixir
smaller = Jido.Authoring.Registry.new!(Map.delete(entries, {"my_app/actions/issue_refund", 1}))
{:error, [issue]} = Jido.Authoring.decode_json(json, registry: smaller, codec: Jido.Agent.Codec)

{issue.code, issue.path}
# => {:reference, ["definition", "extensions", 0, "data", "tools", 1, "id"]}
```

Encoding with a missing entry fails too, with
`authoring Registry has no reference for the required value`. Import also
re-validates `config` against the Flow schema: a stored `"model_calls": 99`
returns an `:invalid_value` issue at
`["definition", "extensions", 0, "data", "config", "limits", "model_calls"]`.

Use referenced Flows for stored definitions. An inline Flow's module name is
generated, so it has no stable Registry key to review.

## Compose With Core Agents

`use Jido.AI.Agent` owns the Agent's `state` and `routes` sections. A second
`state do` or `routes do` block fails with
`Agent section state can be declared only once`. Everything else from core
Jido composes as usual:

| You want | Use |
| --- | --- |
| Static data on the definition | An Extension, through `extensions:` |
| A state field next to `session` | A Plugin with `state_spec/1` |
| Behavior around every Signal | A Plugin with `prepare/2`, `admit/3`, or `reduce/2` |
| A live process per Agent | A Plugin runtime |

This Plugin counts requests in its own `ledger` field:

```elixir
defmodule MyApp.RequestLedger do
  use Jido.Plugin

  alias Jido.Agent.Plugin.Reduction

  @impl true
  def state_spec(_opts) do
    {:ledger,
     Zoi.object(%{requests: Zoi.integer() |> Zoi.min(0)})
     |> Zoi.default(%{requests: 0})}
  end

  @impl true
  def reduce(%Reduction{plugin_state: ledger}, _opts),
    do: {:ok, %{ledger | requests: ledger.requests + 1}}
end

defmodule MyApp.Audit do
  use Jido.Agent.Extension, id: "my_app/audit"
end

defmodule MyApp.DeskAgent do
  use Jido.AI.Agent,
    id: "my_app/desk_agent",
    vsn: 1,
    name: "desk_agent",
    extensions: [MyApp.Audit]

  plugins do
    plugin MyApp.RequestLedger
  end

  ai do
    reasoning Jido.AI.Reasoning.ReAct

    tools do
      action MyApp.LookupOrder
    end
  end
end
```

With one text answer queued in the offline model from
[Getting Started](getting-started.livemd):

```elixir
agent = MyApp.DeskAgent.instantiate!(id: "desk-1")
agent.state
# => %{session: nil, ledger: %{requests: 0}}

request =
  MyApp.DeskAgent.request_signal!(%{
    input: "Where is order A-1001?",
    options: MyApp.OfflineModel.options()
  })

{:ok, next_agent, [_reply]} = MyApp.DeskAgent.cmd(agent, request)
{next_agent.state.ledger, next_agent.state.session.rev}
# => {%{requests: 1}, 4}
```

ReAct reads `context.agent_state`, replaces only `session`, and returns the
rest unchanged, so the Plugin's `reduce/2` owns `ledger`. A custom Flow must
do the same: return every state field it received. The Agent validates the
complete state after each request.

For the Extension and Plugin contracts, see
[Extensions or Plugins](https://hexdocs.pm/jido/extensions-and-plugins.html).
To run the composed Agent as a process, see
[Pure or Live Execution](pure-or-live-execution.md).
