# Dynamic Tool Sources

Some tools aren't known when your Agent compiles: a help center per locale, a
tenant's connected services, an MCP-style server chosen at run time. A
`Jido.AI.ToolSource` lets the code that runs the Agent add those tools to one
request, next to the static Actions from the `tools` block. Read
[Action Tools](action-tools.livemd) first.

```elixir
MyApp.SupportAgent.cmd(agent, request,
  context: %{jido_ai_tool_sources: [{MyApp.HelpCenterTools, %{locale: "en"}}]}
)
```

The model now sees `lookup_order` from the Agent and `search_help_center`
from the source.

## The Trust Boundary

| Who | Can do | Can't do |
| --- | --- | --- |
| Agent definition | Declare static Action tools. | Change at run time. |
| Execution host | Add sources through the execution context. | Remove static tools. |
| Request data | Hide, require, or review tools through `tool_policy`. | Add any tool or source. |

The execution host is your code that calls `cmd/3`,
`Jido.AgentServer.call/3`, or `Jido.AgentServer.submit/3`. It passes sources
in the `context:` option under the `:jido_ai_tool_sources` key. That context
never comes from the Signal.

Request data can't name a source. The ReAct input schema rejects unknown keys:

```elixir
signal =
  Jido.Signal.new!(
    "jido.ai.request",
    %{input: "Hi", jido_ai_tool_sources: [{MyApp.HelpCenterTools, %{locale: "en"}}]},
    source: "/my_app/client"
  )

{:error, error} = MyApp.SupportAgent.cmd(agent, signal)
Exception.message(error)
# => "unrecognized key: jido_ai_tool_sources"
```

## Write a Source

A source implements two callbacks. `list_tools/2` returns definitions.
`run_tool/3` runs one validated call:

```elixir
defmodule MyApp.HelpCenterTools do
  @behaviour Jido.AI.ToolSource

  @articles %{
    "en" => [%{id: "returns-101", title: "Start a return"}],
    "fr" => [%{id: "retours-101", title: "Demander un retour"}]
  }

  @impl Jido.AI.ToolSource
  def list_tools(%{locale: locale}, _context) do
    {:ok,
     [
       %{
         name: "search_help_center",
         description: "Search the #{locale} help center. Returns article IDs and titles.",
         parameter_schema: [query: [type: :string, required: true, doc: "Search terms"]]
       }
     ]}
  end

  @impl Jido.AI.ToolSource
  def run_tool(%{name: "search_help_center", arguments: %{query: _query}}, %{locale: locale}, _context) do
    {:ok, %{locale: locale, articles: Map.fetch!(@articles, locale)}}
  end

  def run_tool(call, _config, _context), do: {:error, {:unknown_tool, call.name}}
end
```

| Callback | Called | Arguments | Returns |
| --- | --- | --- | --- |
| `list_tools(config, context)` | Once per request, before the first model call | Source config and the Action context | `{:ok, [definition]}` or `{:error, reason}` |
| `run_tool(call, config, context)` | Once per model tool call | `%{id, name, arguments}`, config, Action context | `{:ok, value}`, `{:ok, value, effects}`, or `{:error, reason}` |

A definition is a `ReqLLM.Tool` or a map with these keys:

| Key | Default | Notes |
| --- | --- | --- |
| `name` | required | Must be unique across static and dynamic tools. |
| `description` | `""` | The model reads this. |
| `parameter_schema` | `[]` | NimbleOptions keyword list or JSON Schema map. |
| `strict` | `true` | Only `false` turns it off. A `ReqLLM.Tool` keeps its own `strict` value. |
| `provider_options` | `%{}` | Passed to ReqLLM. |

The `callback` of a `ReqLLM.Tool` is dropped. Calls always run through
`run_tool/3` inside the Agent graph.

## Argument Validation

`Jido.AI.Toolset.resolve_call/2` validates arguments with the definition before
`run_tool/3` runs:

| `parameter_schema` | Local validation | `call.arguments` |
| --- | --- | --- |
| Keyword list | Types and required keys are checked. A bad call fails with `{:invalid_tool_arguments, name}`. | Atom keys, such as `%{query: "return"}` |
| JSON Schema map | None. The map is sent to the provider as is. | The model's map, with string keys |

Use a keyword schema when you can. With a JSON Schema map, validate inside
`run_tool/3`; `strict: true` asks the provider to follow the schema, but
Jido AI doesn't enforce it.

## Load and Inspect

`Jido.AI.ToolSource.load/1` runs the same loading that a request does. Use it
in tests:

```elixir
sources = [{MyApp.HelpCenterTools, %{locale: "en"}}]
{:ok, [tool]} = Jido.AI.ToolSource.load(%{jido_ai_tool_sources: sources})

tool
# => %{
#      kind: :source,
#      name: "search_help_center",
#      description: "Search the en help center. Returns article IDs and titles.",
#      parameter_schema: [query: [type: :string, required: true, doc: "Search terms"]],
#      strict: true,
#      provider_options: %{},
#      source: %{module: MyApp.HelpCenterTools, config: %{locale: "en"}}
#    }
```

A loaded tool is plain data. It holds the source module and config, never a
function or process. The request stores it, so a durable turn that resumes
after a restart keeps the same tool set without calling `list_tools/2` again.

## Run a Request

Pass the sources in the execution context:

```elixir
agent = MyApp.SupportAgent.instantiate!(id: "support-1")
request = MyApp.SupportAgent.request_signal!(%{input: "How do I return a jacket?"})

{:ok, agent, [%Jido.Agent.Directive.Reply{signal: reply}]} =
  MyApp.SupportAgent.cmd(agent, request, context: %{jido_ai_tool_sources: sources})
```

With a live Agent, use the same option:

```elixir
Jido.AgentServer.call(server, request, context: %{jido_ai_tool_sources: sources})
```

The model request lists `["lookup_order", "search_help_center"]`. Static tools
come first, in declaration order, then each source's tools in source order.

The tool attempt names the source instead of an Action:

```elixir
[attempt] = reply.data.tool_attempts
Map.take(attempt, [:tool, :status, :input, :output])
# => %{
#      tool: %{kind: :source, name: "search_help_center", source: "Elixir.MyApp.HelpCenterTools"},
#      status: :ok,
#      input: %{"query" => "return"},
#      output: %{
#        "articles" => [%{"id" => "returns-101", "title" => "Start a return"}],
#        "locale" => "en"
#      }
#    }
```

## Merge With Static Tools

`Jido.AI.Reasoning.Actions.StartRequest` builds the request tool set in this
order:

1. Static Actions from the Agent's `tools` block.
2. Tools from each source in `:jido_ai_tool_sources`, in list order.
3. `Jido.AI.Toolset.select/2` applies the request `tool_policy`.

`tool_policy` treats dynamic tools like static ones. It can name
`search_help_center` in `visible`, `hidden`, or `review` while the source is
loaded. Without the source, the same policy fails with
`{:unknown_tool, "search_help_center"}`.

Names must be unique across the merged set. A source that returns
`lookup_order` fails the request with `:duplicate_tools`. There's no override
or shadowing.

## Errors

A loading error fails the whole request before any model call. `cmd/3`
returns `{:error, %Jido.Action.Error.ExecutionFailureError{}}` with the reason
in `error.details.reason`:

| Cause | Reason |
| --- | --- |
| `:jido_ai_tool_sources` isn't a list | `:invalid_tool_sources` |
| Module doesn't export `list_tools/2` and `run_tool/3` | `{:invalid_tool_source, module}` |
| A spec that isn't `module` or `{module, config}` | `:invalid_tool_source` |
| Config holds a pid, reference, or function | `{:nonportable_tool_source, path}`, such as `[:tool_source, 1, :owner]` |
| `list_tools/2` raises | `{:tool_source_failed, module, message}` |
| `list_tools/2` returns `{:error, reason}` | `reason` |
| A definition isn't a map or `ReqLLM.Tool` | `:invalid_tool_source_definition` |
| Two tools share a name | `:duplicate_tools` |

A `run_tool/3` failure doesn't fail the request. `{:error, reason}`, a raise,
or an invalid return becomes an error tool result that the model reads in its
next call. `{:error, :index_unavailable}` reaches the model as:

```elixir
%{
  "status" => "error",
  "error" => %{
    "type" => "execution_error",
    "message" => "index_unavailable",
    "retryable" => false
  }
}
```

[Tool Execution and Results](tool-execution-and-results.md) covers error
results and output limits, which apply to source tools the same way.

## Config Must Be Portable

Source specs and definitions are stored with the request. Keep config to
strings, numbers, atoms, lists, and maps. Pass a registered name or an ID, not
a pid. Look up credentials inside `run_tool/3` from your application, not from
config, so secrets don't land in stored turn data.

`run_tool/3` receives the Action context, which includes `agent_id` and
`agent_state`. Use it for per-Agent lookups.

## Next

- [Tool Execution and Results](tool-execution-and-results.md) – what happens
  between a model tool call and the next model call.
- [Tool Review and Cycle Limits](tool-review-and-cycle-limits.livemd) – require
  approval for a dynamic tool through `tool_policy.review`.
- [Security and Portability](security-and-portability.md) – tool trust and
  portable data.
