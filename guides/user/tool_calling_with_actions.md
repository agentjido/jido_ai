# Tool Calling With Actions

You want model-selected tool calls with `Jido.Action` modules, plus deterministic terminal shapes for one-shot and multi-turn runs.

After this guide, you can use:
- `Jido.AI.Actions.ToolCalling.CallWithTools`
- `Jido.AI.Actions.ToolCalling.ExecuteTool`
- `Jido.AI.Actions.ToolCalling.ListTools`

## Define A Tool Action

```elixir
defmodule MyApp.Actions.Multiply do
  use Jido.Action,
    name: "multiply",
    schema: Zoi.object(%{a: Zoi.integer(), b: Zoi.integer()})

  @impl true
  def run(%{a: a, b: b}, _context), do: {:ok, %{product: a * b}}
end
```

## One-Shot Tool Calling (`CallWithTools`)

One-shot mode returns a terminal turn map without executing tools automatically.

```elixir
alias Jido.AI.Actions.ToolCalling.CallWithTools

params = %{
  prompt: "What is 6 * 7?",
  tools: ["multiply"]
}

context = %{
  tools: %{"multiply" => MyApp.Actions.Multiply}
}

{:ok, result} = Jido.Exec.run(CallWithTools, params, context)
# result.type == :tool_calls or :final_answer
```

## Auto-Execute Tool Loop (`CallWithTools`)

Auto-execute mode runs tools and continues until a final answer or max-turn limit.

```elixir
alias Jido.AI.Actions.ToolCalling.CallWithTools

params = %{
  prompt: "Use multiply to compute 6 * 7 and explain briefly.",
  tools: ["multiply"],
  auto_execute: true,
  max_turns: 5
}

context = %{
  tools: %{"multiply" => MyApp.Actions.Multiply}
}

{:ok, result} = Jido.Exec.run(CallWithTools, params, context)
# result.type == :final_answer when loop completes
# result.turns includes executed loop turns
# result.messages includes assistant/tool conversation messages
```

Deterministic terminal shapes:
- completed loop: `%{type: :final_answer, text: text, usage: usage, turns: turns, messages: messages, model: model}`
- max turns reached: `%{type: :tool_calls, reason: :max_turns_reached, turns: max_turns, usage: usage, model: model}`

## Direct Tool Execution (`ExecuteTool`)

Use direct execution when your app already chose the tool and args.

```elixir
alias Jido.AI.Actions.ToolCalling.ExecuteTool

params = %{
  tool_name: "multiply",
  params: %{a: 6, b: 7}
}

context = %{
  tools: %{"multiply" => MyApp.Actions.Multiply}
}

{:ok, result} = Jido.Exec.run(ExecuteTool, params, context)
# %{tool_name: "multiply", status: :success, result: %{product: 42}}
```

## Tool Discovery And Security Filtering (`ListTools`)

`ListTools` defaults to excluding sensitive tool names (`include_sensitive: false`) and returns only public metadata (`name`, optional serialized `schema`).

```elixir
alias Jido.AI.Actions.ToolCalling.ListTools

context = %{
  tools: %{
    "multiply" => MyApp.Actions.Multiply,
    "admin_delete_user" => MyApp.Actions.AdminDeleteUser
  }
}

{:ok, public_tools} = Jido.Exec.run(ListTools, %{}, context)
{:ok, all_tools} = Jido.Exec.run(ListTools, %{include_sensitive: true}, context)
{:ok, allowlisted} = Jido.Exec.run(ListTools, %{allowed_tools: ["multiply"]}, context)
```

Security filtering behavior:
- default denylist filtering by sensitive name fragments (`admin`, `delete`, `token`, `secret`, etc.)
- explicit override with `include_sensitive: true`
- optional allowlist hard filter with `allowed_tools: [...]`

## Tool Registry Precedence (Tool Map / Context / Plugin State)

`CallWithTools`, `ExecuteTool`, and `ListTools` resolve tool registries with this precedence:

1. `context[:tools]`
2. `context[:tool_calling][:tools]`
3. `context[:chat][:tools]`
4. `context[:state][:tool_calling][:tools]`
5. `context[:state][:chat][:tools]`
6. `context[:agent][:state][:tool_calling][:tools]`
7. `context[:agent][:state][:chat][:tools]`
8. `context[:plugin_state][:tool_calling][:tools]`
9. `context[:plugin_state][:chat][:tools]`

First non-`nil` registry wins. This keeps behavior deterministic across direct action execution, plugin-routed calls, and fallback context paths.

## Dynamic Registration On A Running Agent

```elixir
{:ok, _agent} = Jido.AI.register_tool(agent_pid, MyApp.Actions.Multiply)
{:ok, true} = Jido.AI.has_tool?(agent_pid, "multiply")
```

## Failure Mode: Tool Execution Returns `:not_found`

Symptom:
- `ExecuteTool` returns tool-not-found error content

Fix:
- pass a tools map in one of the registry precedence paths above
- verify `module.name/0` matches the requested `tool_name`

## Defaults You Should Know

- `CallWithTools` `auto_execute` default: `false`
- `CallWithTools` `max_turns` default: `10` (hard-capped by validation)
- `ExecuteTool` timeout default: `30_000ms`
- `ListTools` schema inclusion default: `true`
- `ListTools` sensitive filtering default: enabled (`include_sensitive: false`)

## Next

- [Actions Catalog](../developer/actions_catalog.md)
- [Plugins And Actions Composition](../developer/plugins_and_actions_composition.md)
