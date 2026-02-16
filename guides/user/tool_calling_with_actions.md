# Tool Calling With Actions

You want LLM tool calls backed by normal `Jido.Action` modules, with safe execution and clear boundaries.

After this guide, you can adapt actions to tools, execute them with `Executor`, and manage runtime tool registration.

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

## Convert Actions To LLM Tool Schemas

```elixir
tools = Jido.AI.ToolAdapter.from_actions([MyApp.Actions.Multiply], strict: true)
```

`ToolAdapter` is schema-focused. Execution still belongs to your runtime path.

## Execute A Tool Safely

```elixir
tools_map = Jido.AI.Executor.build_tools_map([MyApp.Actions.Multiply])

{:ok, result} =
  Jido.AI.Executor.execute(
    "multiply",
    %{"a" => "6", "b" => "7"},
    %{},
    tools: tools_map,
    timeout: 5_000
  )
```

## Dynamically Register A Tool On A Running Agent

```elixir
{:ok, _agent} = Jido.AI.register_tool(agent_pid, MyApp.Actions.Multiply)
{:ok, true} = Jido.AI.has_tool?(agent_pid, "multiply")
```

## Failure Mode: Tool Execution Returns `:not_found`

Symptom:
- `Executor.execute/4` returns tool not found

Fix:
- pass `tools:` map built from your modules
- verify `module.name/0` matches requested tool name

## Defaults You Should Know

- `Executor` timeout default: `30_000ms`
- `register_tool/3` call timeout default: `5_000ms`
- `ToolAdapter` strict mode default: inferred by action `strict?/0` (else `false`)

## When To Use / Not Use

Use this approach when:
- tools are first-class part of agent reasoning
- you need schema-accurate tool definitions for providers

Do not use this approach when:
- your flow is fully deterministic and does not require model-selected tool calls

## Next

- [Streaming Workflows](streaming_workflows.md)
- [Plugins And Actions Composition](../developer/plugins_and_actions_composition.md)
- [Actions Catalog](../developer/actions_catalog.md)
