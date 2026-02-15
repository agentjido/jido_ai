# Namespace Breaking Changes Matrix (2.0-beta)

## Signal Types
- `react.input` -> `ai.react.query`
- `react.cancel` -> `ai.react.cancel`
- `react.register_tool` -> `ai.react.register_tool`
- `react.unregister_tool` -> `ai.react.unregister_tool`
- `react.set_tool_context` -> `ai.react.set_tool_context`
- `cot.query` -> `ai.cot.query`
- `tot.query` -> `ai.tot.query`
- `got.query` -> `ai.got.query`
- `trm.query` -> `ai.trm.query`
- `adaptive.query` -> `ai.adaptive.query`
- `react.llm.request` -> `ai.llm.request`
- `react.llm.response` -> `ai.llm.response`
- `react.llm.delta` -> `ai.llm.delta`
- `react.llm.error` -> `ai.llm.error`
- `react.llm.cancelled` -> `ai.llm.cancelled`
- `react.tool.call` -> `ai.tool.call`
- `react.tool.result` -> `ai.tool.result`
- `react.tool.error` -> `ai.tool.error`
- `react.embed.request` -> `ai.embed.request`
- `react.embed.result` -> `ai.embed.result`
- `react.embed.error` -> `ai.embed.error`
- `react.usage` -> `ai.usage`
- `react.request.started` -> `ai.request.started`
- `react.request.completed` -> `ai.request.completed`
- `react.request.failed` -> `ai.request.failed`
- `react.request.error` -> `ai.request.error`
- `react.step` -> `ai.react.step`

## Payload changes
- `RequestError` / `EmitRequestError`: `call_id` -> `request_id`

## ReAct action atoms
- `:react_start` -> `:ai_react_start`
- `:react_llm_result` -> `:ai_react_llm_result`
- `:react_tool_result` -> `:ai_react_tool_result`
- `:react_llm_partial` -> `:ai_react_llm_partial`
- `:react_cancel` -> `:ai_react_cancel`
- `:react_request_error` -> `:ai_react_request_error`
- `:react_register_tool` -> `:ai_react_register_tool`
- `:react_unregister_tool` -> `:ai_react_unregister_tool`
- `:react_set_tool_context` -> `:ai_react_set_tool_context`

## ReAct action spec names
- `react.*` -> `ai.react.*`
