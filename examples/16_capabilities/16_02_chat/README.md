# Chat capability and callable Actions

The [Agent example](agent.ex) declares
the Chat Plugin and seven explicit routes beside an ordinary domain route.
The [example tests](../../../test/examples/16_capabilities/16_02_chat/16_02_chat_test.exs)
use one HTTP mock. ReqLLM, core Flow, tool Actions and Agent commits execute.
The suite has 32 example cases. Run it with:

```sh
mix test test/examples/16_capabilities/16_02_chat/16_02_chat_test.exs --include example --seed 0
```

## Public contract

| Signal | Public Action | Result retained |
| --- | --- | --- |
| `chat.simple` | `Jido.AI.Actions.LLM.Chat` | `text`, `model`, three token counts in `usage` |
| `chat.complete` | `Jido.AI.Actions.LLM.Complete` | Same text result; no system prompt |
| `chat.embed` | `Jido.AI.Actions.LLM.Embed` | `embeddings`, `count`, `model`, `dimensions` |
| `chat.generate_object` | `Jido.AI.Actions.LLM.GenerateObject` | Decoded `object`, `model`, `usage` |
| `chat.message` | `Jido.AI.Actions.ToolCalling.CallWithTools` | Canonical Turn result; extra turn/history fields after tool execution |
| `chat.execute_tool` | `Jido.AI.Actions.ToolCalling.ExecuteTool` | `tool_name`, formatted `result`, `status: :success` |
| `chat.list_tools` | `Jido.AI.Actions.ToolCalling.ListTools` | Filtered tool names/schemas, count and filter metadata |

Direct `run/2` and core Exec return these result maps. A capability route stores
the result in its declared `into` field and returns the complete domain state.
It preserves unrelated fields. Provider failure preserves committed state.
The shared capability helper uses the prepared Plugin binding; caller payloads
cannot select another Action or result field.

`Jido.AI.Plugins.Chat` provides its name, description, category, tags, version,
state key, action list, schema and Signal-pattern helpers. Use keyword config
and core `state_spec/1`. Declare the routes
returned by `signal_routes/1`, which now target `Actions.Chat.RunCapability`.
The old pass-through `handle_signal/2`, `transform_result/3` and `plugin_spec/1`
are replaced by the core Plugin lifecycle and Agent definition.

## Defaults and input

The Plugin retains its defaults: capable model, 4096 tokens, temperature 0.7,
no system prompt, automatic tool execution, ten tool rounds, an empty tool
map and `tool_policy: :allow_all`. `tool_policy` remains descriptive state;
it did not enforce authorization in the baseline. Discovery's sensitive-name
filter is also not an execution policy.

Explicit Action parameters win, including values equal to schema defaults and
`auto_execute: false`. Caller defaults precede Plugin defaults. Known string
parameter keys are converted before core validation. Current Agent structs can
supply defaults. Planning shares this input/default helper.
Generation parameters override top-level provider options. ReqLLM retains its
own precedence for nested transport options. Caller `model_options` must be a
keyword list. Completion discards system prompt input and defaults.

Direct Chat, Complete and GenerateObject keep their fast model alias, 1024-token
and 0.7-temperature defaults. Direct CallWithTools uses the capable alias and
does not execute tools by default. Direct Embed uses the embedding alias when
no caller or Plugin model is supplied. A configured conversational model does
not automatically become an embedding model; supply an embedding model for
that route.

Empty or invalid prompts and embedding entries fail before HTTP work. Embed
now rejects an empty input list and simultaneous `texts`/`texts_list` inputs.
An empty provider vector list remains a successful result with zero dimensions.
GenerateObject validates returned objects with the shared Output validator or
ReqLLM's keyword-schema validator. Nested Zoi keys and enum labels are checked.
It retains the decoded object's key/value forms and adds no AI repair call.
Invalid typed output is now an error instead of an unchecked successful map.

## Flow and execution

The callable tool loop uses core Flow dispatch, shared Models, Turn, ToolAdapter,
Usage and Exec. It has no separate executor or supervisor. It preserves the
callable Action's distinct contract:

- `max_turns` counts tool rounds. Zero permits the first model request but no
  tool execution. Validation caps the limit at 50.
- A limit result retains pending tools, `reason: :max_turns_reached`, the limit
  and accumulated usage. It has no `messages` field.
- Successful automatic execution returns the complete serialized conversation,
  executed round count and accumulated usage. Each assistant response occurs
  once; the duplicate message in the old recursive loop was removed.
- Unknown or invalid tools become error tool messages. The model can recover.
  A provider failure returns an error tuple through core execution, including
  a failure after completed tool work. A failed capability call does not commit
  an error-shaped value as a successful Agent result.
- Names used for advertisement, filtering and lookup agree, including aliases.
  A registered core Flow can be a tool. Returned tool effects are not applied
  to the host by these standalone callable Actions.

Actual next-request checks prove OpenAI Responses continuation IDs and decoded
reasoning details. Two tool rounds prove message order, options, call IDs and
nested usage. Held provider connections prove timeout and Exec cancellation
stop the provider worker inside the Flow.

## Observation and callbacks

All four LLM Actions use `[:jido, :ai, :llm, event]`. Operation and supplied IDs
remain metadata. Start precedes validation; it does not prove an HTTP call.
Successful telemetry reports decoded token counts. Embed now requests usage
from ReqLLM while retaining its public vector result. The mock proves five
embedding tokens, rather than a fabricated zero. Empty embedding results and
invalid inputs no longer crash telemetry calculation.

`Jido.AI.Actions.Helpers` and `Jido.AI.Validation` retain their public functions.
Default callback execution uses core Exec without a separate task supervisor.
Explicit caller Task supervisors remain supported. Tests prove arbitrary return
values, bounded execution, failure and worker cleanup. Existing multiline
validation cases from PR 290 remain, with an HTTP example for accepted input.

## Remaining limits

This example does not cover all provider formats, runtime tool catalog mutation,
or durable recovery. Direct callable
Actions do not add native session history, approval controls or tool lifecycle
Signals. Callable error metadata and descriptive `tool_policy` need explicit
consumer guidance at cutover. Invalid structured output retains completed provider usage in Action error
telemetry and leaves the Agent result unchanged. Other failed-request, quota
and recovery accounting cases remain required.

Four native Chat contract tests and the Helper and Validation tests supplement
the example suite.
