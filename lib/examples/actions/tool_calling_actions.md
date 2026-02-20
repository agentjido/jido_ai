# Tool Calling Action Snippets

Run these from the repository root with provider credentials configured.

## CallWithTools One-Shot

```bash
mix run -e 'alias Jido.AI.Actions.ToolCalling.CallWithTools; alias Jido.AI.Examples.Tools.ConvertTemperature; context = %{tools: %{ConvertTemperature.name() => ConvertTemperature}}; {:ok, result} = Jido.Exec.run(CallWithTools, %{prompt: "Use convert_temperature for 72F to C.", tools: [ConvertTemperature.name()]}, context); IO.inspect(result, label: "call_with_tools_one_shot")'
```

One-shot mode returns a single terminal turn (`:tool_calls` or `:final_answer`).

## CallWithTools Auto-Execute

```bash
mix run -e 'alias Jido.AI.Actions.ToolCalling.CallWithTools; alias Jido.AI.Examples.Tools.ConvertTemperature; context = %{tools: %{ConvertTemperature.name() => ConvertTemperature}}; {:ok, result} = Jido.Exec.run(CallWithTools, %{prompt: "Use convert_temperature for 72F to C and explain.", tools: [ConvertTemperature.name()], auto_execute: true, max_turns: 5}, context); IO.inspect(result, label: "call_with_tools_auto_execute")'
```

Auto-execute mode returns a deterministic terminal map with `turns`, `usage`, and `messages`.

## ExecuteTool Direct

```bash
mix run -e 'alias Jido.AI.Actions.ToolCalling.ExecuteTool; alias Jido.AI.Examples.Tools.ConvertTemperature; context = %{tools: %{ConvertTemperature.name() => ConvertTemperature}}; {:ok, result} = Jido.Exec.run(ExecuteTool, %{tool_name: ConvertTemperature.name(), params: %{value: 72.0, from: "fahrenheit", to: "celsius"}}, context); IO.inspect(result, label: "execute_tool_direct")'
```

Use this when your app chooses the tool and arguments directly.

## ListTools Discovery And Security Filtering

```elixir
alias Jido.AI.Actions.ToolCalling.ListTools

context = %{
  tools: %{
    "convert_temperature" => Jido.AI.Examples.Tools.ConvertTemperature,
    "admin_delete_user" => MyApp.Actions.AdminDeleteUser
  }
}

{:ok, public_view} = Jido.Exec.run(ListTools, %{}, context)
{:ok, full_view} = Jido.Exec.run(ListTools, %{include_sensitive: true}, context)
{:ok, allowlisted} = Jido.Exec.run(ListTools, %{allowed_tools: ["convert_temperature"]}, context)
```

Default behavior excludes sensitive tool names unless `include_sensitive: true` is set.
