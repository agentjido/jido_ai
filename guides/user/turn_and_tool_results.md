# Turn And Tool Results

You want to normalize raw LLM responses, classify them, execute tool calls, and project messages for follow-up LLM turns.

After this guide, you can:
- Build a `Jido.AI.Turn` from any provider response
- Check whether a turn requests tool execution
- Execute all requested tools and collect results
- Project assistant + tool messages for multi-turn LLM loops
- Execute tools directly without an LLM response
- Extract text from diverse provider response shapes
- Subscribe to tool execution telemetry events

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

## Build A Turn From A Raw LLM Response

`from_response/2` normalizes any `ReqLLM.Response`, raw provider map, or existing turn into a canonical `%Jido.AI.Turn{}`.

```elixir
alias Jido.AI.Turn

# From a ReqLLM response returned by Jido.AI.generate_text/2
{:ok, response} = Jido.AI.generate_text(messages, model: "anthropic:claude-sonnet-4-20250514")
turn = Turn.from_response(response)

# Override the model field
turn = Turn.from_response(response, model: "my-custom-tag")
```

The turn struct contains:
- `type` — `:tool_calls` or `:final_answer`
- `text` — extracted text content
- `thinking_content` — extended thinking output (or `nil`)
- `tool_calls` — normalized list of tool call maps
- `usage` — token usage metadata
- `model` — model identifier
- `tool_results` — populated after tool execution

You can also build from an already-classified map:

```elixir
turn = Turn.from_result_map(%{type: :final_answer, text: "42", usage: %{input_tokens: 10}})
```

## Check If Tools Are Needed

```elixir
if Turn.needs_tools?(turn) do
  # turn.type == :tool_calls or turn.tool_calls is non-empty
  IO.puts("LLM wants to call #{length(turn.tool_calls)} tool(s)")
else
  IO.puts("Final answer: #{turn.text}")
end
```

## Run All Requested Tools

`run_tools/3` executes every tool call in the turn and returns an updated turn with `tool_results` attached.

```elixir
tools = Turn.build_tools_map([MyApp.Actions.Multiply])

context = %{tools: tools}

{:ok, updated_turn} = Turn.run_tools(turn, context)

# Each tool result has this shape:
# %{
#   id: "call_abc",
#   name: "multiply",
#   content: "{\"product\":42}",
#   raw_result: {:ok, %{product: 42}, []}
# }
```

You can also pass tools via opts:

```elixir
{:ok, updated_turn} = Turn.run_tools(turn, %{}, tools: tools, timeout: 10_000)
```

## Project Messages For Follow-Up LLM Calls

After running tools, project the assistant message and tool result messages back into the conversation:

```elixir
assistant_msg = Turn.assistant_message(updated_turn)
# %{role: :assistant, content: "...", tool_calls: [...]}

tool_msgs = Turn.tool_messages(updated_turn)
# [%{role: :tool, tool_call_id: "call_abc", name: "multiply", content: "{\"product\":42}"}]
```

Append both to your message history for the next LLM call.

## Complete Custom Tool-Calling Loop

This loop calls the LLM, normalizes to a Turn, executes tools, projects messages, and calls the LLM again until a final answer is reached.

```elixir
alias Jido.AI.Turn

defmodule MyApp.ToolLoop do
  @max_iterations 5

  def run(initial_messages, tools_map) do
    loop(initial_messages, tools_map, 0)
  end

  defp loop(_messages, _tools_map, @max_iterations) do
    {:error, :max_iterations_reached}
  end

  defp loop(messages, tools_map, iteration) do
    # 1. Call the LLM
    {:ok, response} =
      Jido.AI.generate_text(
        messages,
        model: "anthropic:claude-sonnet-4-20250514",
        tools: Map.keys(tools_map)
      )

    # 2. Normalize to a Turn
    turn = Turn.from_response(response)

    # 3. Check if the LLM wants tools
    if Turn.needs_tools?(turn) do
      # 4. Execute all requested tools
      {:ok, executed_turn} = Turn.run_tools(turn, %{tools: tools_map})

      # 5. Project assistant + tool messages
      assistant_msg = Turn.assistant_message(executed_turn)
      tool_msgs = Turn.tool_messages(executed_turn)

      # 6. Append to history and loop
      updated_messages = messages ++ [assistant_msg | tool_msgs]
      loop(updated_messages, tools_map, iteration + 1)
    else
      # Final answer — return the turn
      {:ok, turn}
    end
  end
end

# Usage:
tools_map = Turn.build_tools_map([MyApp.Actions.Multiply])

messages = [
  %{role: :system, content: "You are a calculator. Use the multiply tool."},
  %{role: :user, content: "What is 6 * 7?"}
]

{:ok, final_turn} = MyApp.ToolLoop.run(messages, tools_map)
IO.puts(final_turn.text)
```

## Direct Tool Execution

Use `execute/4` when you know the tool name and want to call it outside an LLM loop:

```elixir
tools = Turn.build_tools_map([MyApp.Actions.Multiply])

{:ok, result, effects} = Turn.execute("multiply", %{"a" => 6, "b" => 7}, %{}, tools: tools)
# result == %{product: 42}
# effects == []
```

Use `execute_module/4` when you have the module reference directly:

```elixir
{:ok, result, effects} = Turn.execute_module(MyApp.Actions.Multiply, %{a: 6, b: 7}, %{})
# result == %{product: 42}
# effects == []
```

Both functions normalize parameters against the action schema automatically, so string-keyed maps from LLM JSON output work without manual conversion.

## Result Envelope Contract

Tool execution envelopes are canonical triples:

- `{:ok, result, effects}`
- `{:error, reason, effects}`

Legacy 2-tuples (`{:ok, result}` / `{:error, reason}`) are normalized at runtime boundaries.
Use triple pattern-matching in new code.

## Effect Policy And Ordering

- `Turn.execute/4` and `Turn.execute_module/4` filter tool-emitted effects through `context[:effect_policy]` when provided.
- Disallowed effects are dropped; allowed effects remain in the returned `effects` list.
- Tool call execution order in `run_tools/3` follows the order of `turn.tool_calls`.

## Text Extraction

`extract_text/1` normalizes diverse provider response shapes into a plain string:

```elixir
Turn.extract_text("hello")
# "hello"

Turn.extract_text(%{message: %{content: "hello"}})
# "hello"

Turn.extract_text(%{choices: [%{message: %{content: "hello"}}]})
# "hello"

Turn.extract_text(nil)
# ""
```

Use `extract_from_content/1` when you already have the content value (not wrapped in a response envelope):

```elixir
Turn.extract_from_content([%{type: :text, text: "part 1"}, %{type: :text, text: "part 2"}])
# "part 1\npart 2"
```

## Telemetry Events

Tool execution emits `:telemetry` events via `Jido.AI.Observe`:

| Event | Path | Measurements | Key Metadata |
|---|---|---|---|
| start | `[:jido, :ai, :tool, :execute, :start]` | `system_time` | `tool_name`, `params`, `call_id`, `run_id`, `agent_id`, `iteration` |
| stop | `[:jido, :ai, :tool, :execute, :stop]` | `duration_ms`, `duration` | `tool_name`, `result`, `call_id`, `run_id`, `agent_id`, `thread_id` |
| exception | `[:jido, :ai, :tool, :execute, :exception]` | `duration_ms`, `duration` | `tool_name`, `reason`, `call_id`, `run_id`, `agent_id`, `thread_id` |

Subscribe example:

```elixir
:telemetry.attach(
  "my-tool-timer",
  Jido.AI.Observe.tool_execute(:stop),
  fn _event, measurements, metadata, _config ->
    IO.puts("#{metadata.tool_name} took #{measurements.duration_ms}ms")
  end,
  nil
)
```

Sensitive parameters are sanitized via `Observe.sanitize_sensitive/1` before emission.

## Failure Mode: Tool Not Found

Symptom:
- `execute/4` or `run_tools/3` returns an error with `type: :not_found`

Fix:
- verify `module.name/0` matches the tool name the LLM requested
- pass the tools map via `context[:tools]`, `opts[:tools]`, or `context[:tool_calling][:tools]`
- inspect with `Turn.build_tools_map([YourModule])` to see registered names

## Failure Mode: Tool Execution Timeout

Symptom:
- tool result contains `type: :timeout` error

Fix:
- increase timeout: `Turn.run_tools(turn, context, timeout: 60_000)`
- check that the action's `run/2` completes within the configured timeout

## Defaults You Should Know

- Tool execution timeout: `30_000ms`
- `from_response/2` defaults `type` to `:final_answer` when no tool calls are present
- `from_response/2` defaults `text` to `""` when content is nil
- `tool_results` starts as `[]` — populated only after `run_tools/3` or `with_tool_results/2`
- `run_tools/3` on a turn with no tool calls returns `{:ok, turn}` unchanged
- `needs_tools?/1` checks both `type == :tool_calls` and non-empty `tool_calls` list
- tool execution result envelopes always include an effects list (`{:ok|:error, payload, effects}`)

## When To Use / Not Use

Use `Jido.AI.Turn` when:
- you need a custom tool-calling loop with full control over iteration
- you are building a strategy or directive that processes LLM responses
- you need to project assistant + tool messages into conversation history

Do not use `Jido.AI.Turn` when:
- `CallWithTools` with `auto_execute: true` already handles your loop — use that instead
- you only need text from a response — `Jido.AI.ask/2` returns it directly

## Next

- [Tool Calling With Actions](tool_calling_with_actions.md)
- [Thread Context And Message Projection](thread_context_and_message_projection.md)
- [Observability Basics](observability_basics.md)
