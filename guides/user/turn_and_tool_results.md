# Response And Tool Results

You want to normalize raw LLM responses, classify them, execute tool calls, and project messages for follow-up LLM responses.

`Jido.AI.Model.Response` is a response value and message projection. It does not execute
tools. `Jido.AI.Tools.Executor` owns direct tool execution. Native Profile
requests use the same target execution boundary with their own limits,
interception, and effect policy. Use Agent + DSL + Profile for ordinary agents;
the direct APIs below are for explicit lower-level composition.

After this guide, you can:
- Build a `Jido.AI.Model.Response` from any provider response
- Check whether a response requests tool execution
- Execute all requested tools and collect results
- Project assistant + tool messages for multi-response LLM loops
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

## Build A Response From A Raw LLM Response

`from_response/2` normalizes any `ReqLLM.Response`, raw provider map, or existing response into a canonical `%Jido.AI.Model.Response{}`.

```elixir
alias Jido.AI.Model.Response

# From a native ReqLLM response
{:ok, response} =
  ReqLLM.generate_text("anthropic:claude-sonnet-4-20250514", messages)
response = Response.from_response(response)

# Override the model field
response = Response.from_response(response, model: "my-custom-tag")
```

The response struct contains:
- `type` — `:tool_calls` or `:final_answer`
- `text` — extracted text content
- `content_parts` — ordered ReqLLM content parts, including generated images
- `thinking_content` — extended thinking output (or `nil`)
- `tool_calls` — normalized list of tool call maps
- `usage` — token usage metadata
- `model` — model identifier
- `tool_results` — populated after tool execution

For a text-only response, `Response.result/1` returns the text string. For a
multimodal response, it returns the ordered visible content parts:

```elixir
result = Response.result(response)
images = Response.images(response)
```

Generated images also use `:content_part` `ai.llm.delta` signals while a
response streams. The signal `delta` is the complete
`ReqLLM.Message.ContentPart`.

You can also build from an already-classified map:

```elixir
response = Response.from_result_map(%{type: :final_answer, text: "42", usage: %{input_tokens: 10}})
```

## Check If Tools Are Needed

```elixir
if Response.needs_tools?(response) do
  # response.type == :tool_calls or response.tool_calls is non-empty
  IO.puts("LLM wants to call #{length(response.tool_calls)} tool(s)")
else
  IO.puts("Final answer: #{response.text}")
end
```

## Run All Requested Tools

`run_tools/3` executes every tool call in the response and returns an updated response with `tool_results` attached.

```elixir
tools = Jido.AI.ToolAdapter.to_action_map([MyApp.Actions.Multiply])

context = %{tools: tools}

{:ok, updated_response} = Jido.AI.Tools.Executor.run_tools(response, context)

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
{:ok, updated_response} = Jido.AI.Tools.Executor.run_tools(response, %{}, tools: tools, timeout: 10_000)
```

## Project Messages For Follow-Up LLM Calls

After running tools, project the assistant message and tool result messages back into the context:

```elixir
assistant_msg = Response.assistant_message(updated_response)
# %{role: :assistant, content: "...", tool_calls: [...]}

tool_msgs = Response.tool_messages(updated_response)
# [%{role: :tool, tool_call_id: "call_abc", name: "multiply", content: "{\"product\":42}"}]
```

Append both to your message history for the next LLM call.

## Complete Custom Tool-Calling Loop

This loop calls the LLM, normalizes to a Response, executes tools, projects messages, and calls the LLM again until a final answer is reached.

```elixir
alias Jido.AI.Model.Response

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
      ReqLLM.generate_text(
        "anthropic:claude-sonnet-4-20250514",
        messages,
        tools: Map.keys(tools_map)
      )

    # 2. Normalize to a Response
    response = Response.from_response(response)

    # 3. Check if the LLM wants tools
    if Response.needs_tools?(response) do
      # 4. Execute all requested tools
      {:ok, executed_turn} = Jido.AI.Tools.Executor.run_tools(response, %{tools: tools_map})

      # 5. Project assistant + tool messages
      assistant_msg = Response.assistant_message(executed_turn)
      tool_msgs = Response.tool_messages(executed_turn)

      # 6. Append to history and loop
      updated_messages = messages ++ [assistant_msg | tool_msgs]
      loop(updated_messages, tools_map, iteration + 1)
    else
      # Final answer — return the response
      {:ok, response}
    end
  end
end

# Usage:
tools_map = Jido.AI.ToolAdapter.to_action_map([MyApp.Actions.Multiply])

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
tools = Jido.AI.ToolAdapter.to_action_map([MyApp.Actions.Multiply])

{:ok, result, effects} = Jido.AI.Tools.Executor.execute("multiply", %{"a" => 6, "b" => 7}, %{}, tools: tools)
# result == %{product: 42}
# effects == []
```

Use `execute_module/4` when you have the module reference directly:

```elixir
{:ok, result, effects} = Jido.AI.Tools.Executor.execute_module(MyApp.Actions.Multiply, %{a: 6, b: 7}, %{})
# result == %{product: 42}
# effects == []
```

Both functions normalize parameters against the action schema automatically, so string-keyed maps from LLM JSON output work without manual conversion.

## Result Envelope Contract

Tool execution envelopes are canonical triples:

- `{:ok, result, effects}`
- `{:error, reason, effects}`

Two-tuples (`{:ok, result}` / `{:error, reason}`) are normalized at runtime boundaries.
Use triple pattern-matching in new code.

## ReAct Agent Tool Results

`Jido.AI.Model.Response.tool_results` is the low-level surface used when you build a
custom tool loop yourself. When `Jido.AI.Agent` manages the ReAct loop for you,
inspect completed tool outputs through the agent snapshot:

```elixir
{:ok, status} = Jido.AgentServer.status(pid)

tool_results = status.snapshot.details[:tool_results] || []
```

`status.snapshot.result` remains the final assistant answer. Tool result
entries keep the normalized action envelope under `:result`:

```elixir
%{
  id: "call_abc",
  name: "multiply",
  arguments: %{"a" => 6, "b" => 7},
  result: {:ok, %{product: 42}, []}
}
```

Use `snapshot.details[:context]` for restoring message history, not for
recovering structured tool payloads.

## Effect Policy And Ordering

- `Jido.AI.Tools.Executor.execute/4` and `Jido.AI.Tools.Executor.execute_module/4` filter tool-emitted effects through `context[:effect_policy]` when provided.
- Disallowed effects are dropped; allowed effects remain in the returned `effects` list.
- Tool call execution order in `run_tools/3` follows the order of `response.tool_calls`.
- Tool actions may read runtime state snapshots from `context[:state]` (canonical, core-aligned).
- ReAct/ToT strategy orchestration injects this snapshot key automatically; user-provided values for this key are overridden.

## Text Extraction

`extract_text/1` normalizes diverse provider response shapes into a plain string:

```elixir
Response.extract_text("hello")
# "hello"

Response.extract_text(%{message: %{content: "hello"}})
# "hello"

Response.extract_text(%{choices: [%{message: %{content: "hello"}}]})
# "hello"

Response.extract_text(nil)
# ""
```

Use `extract_from_content/1` when you already have the content value (not wrapped in a response envelope):

```elixir
Response.extract_from_content([%{type: :text, text: "part 1"}, %{type: :text, text: "part 2"}])
# "part 1\npart 2"
```

## Telemetry Events

Tool execution emits `:telemetry` events via `Jido.AI.Observe`:

| Event | Path | Measurements | Key Metadata |
|---|---|---|---|
| start | `[:jido, :ai, :tool, :execute, :start]` | `system_time` | `tool_name`, `params`, `call_id`, `run_id`, `agent_id`, `iteration` |
| stop | `[:jido, :ai, :tool, :execute, :stop]` | `duration_ms`, `duration` | `tool_name`, `result` summary, `call_id`, `run_id`, `agent_id`, `thread_id` |
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

Telemetry metadata is passed through `Observe.sanitize_telemetry_metadata/1` before emission. Sensitive parameters are redacted, large nested values are bounded, and tool `result` metadata is retained as a low-cardinality summary rather than the raw result blob. Tool-result content sent back through the model/tool transport is encoded through `Observe.sanitize_transport_payload/1` so arbitrary action outputs become bounded JSON-safe data.

## Failure Mode: Tool Not Found

Symptom:
- `execute/4` or `run_tools/3` returns an error with `type: :not_found`

Fix:
- verify `module.name/0` matches the tool name the LLM requested
- pass the tools map via `context[:tools]`, `opts[:tools]`, or `context[:tool_calling][:tools]`
- inspect with `Jido.AI.ToolAdapter.to_action_map([YourModule])` to see registered names

## Failure Mode: Tool Execution Timeout

Symptom:
- tool result contains `type: :timeout` error

Fix:
- increase timeout: `Jido.AI.Tools.Executor.run_tools(response, context, timeout: 60_000)`
- check that the action's `run/2` completes within the configured timeout

## Defaults You Should Know

- Tool execution timeout: `30_000ms`
- `from_response/2` defaults `type` to `:final_answer` when no tool calls are present
- `from_response/2` defaults `text` to `""` when content is nil
- `tool_results` starts as `[]` — populated only after `run_tools/3` or `with_tool_results/2`
- `run_tools/3` on a response with no tool calls returns `{:ok, response}` unchanged
- `needs_tools?/1` checks both `type == :tool_calls` and non-empty `tool_calls` list
- tool execution result envelopes always include an effects list (`{:ok|:error, payload, effects}`)

## When To Use / Not Use

Use `Jido.AI.Model.Response` when:
- you need a custom tool-calling loop with full control over iteration
- you are building a strategy or directive that processes LLM responses
- you need to project assistant + tool messages into context history

Do not use `Jido.AI.Model.Response` when:
- `CallWithTools` with `auto_execute: true` already handles your loop — use that instead
- you only need text from a response — use `ReqLLM.Response.text/1`

## Next

- [Tool Calling With Actions](tool_calling_with_actions.md)
- [Context And Message Projection](thread_context_and_message_projection.md)
- [Observability Basics](observability_basics.md)
