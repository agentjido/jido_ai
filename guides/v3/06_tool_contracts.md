# Design a tool contract

A model-callable tool needs a stable name, validated input, a bounded
operation, and a result the model can read. A Jido Action is a good fit for one
operation. A Jido Flow is a good fit for a validated sequence of steps. Declare
either under the Agent's `tools` block; the model sees only the tools that the
profile and request allow.

```elixir
tools do
  action MyApp.LookupPrice, as: :price
  flow MyApp.BuildQuote, as: :quote
end
```

The `as:` name is the model-facing tool identity. Keep it short and stable.
The target schema must reject malformed input before work starts. The target
should return structured data with clear keys. For a Flow, select its complete
output explicitly; do not rely on a reader to infer which step wins. Give
every external I/O operation a timeout and decide whether repeated calls are
safe. A tool can cause effects before the AI answer is committed, so an answer
failure does not undo a charge, email, or database write.

Request execution context can supply trusted services through `tool_context`.
This is not the same as model-selected arguments. Put a client or actor in
execution context, not in a Signal, Thread entry, or portable Agent state.
Keep authorization in application code; a model's choice of a tool name is
not authorization.

The [tool-flow example](../../examples/01_authoring/01_02_tool_flow/README.md)
uses both an Action and a Flow. The [numeric input example](../../examples/03_tools/03_03_numeric_inputs/README.md)
checks the input boundary. Dynamic native tool sources are not part of the
current stable authoring contract. Add tools through a declared target or an
explicit supported adapter. Next, define a [structured result](07_structured_results.md).
