# 02_07: Model response metadata

The [Agent modules](agent.ex)
and [example tests](../../../test/examples/02_requests/02_07_response_metadata/02_07_response_metadata_test.exs)
use the shared HTTP/SSE mock. ReqLLM decodes actual provider response data.
All thinking text and reasoning signatures in this example are synthetic.

```sh
mix test --include example test/examples/02_requests/02_07_response_metadata/02_07_response_metadata_test.exs
```

The example proves these cases:

- Successful ReAct completion stores `:final_answer`. This reason agrees in
  the request record, terminal event and Session inspection. Four cases cover
  plain/streamed calls with and without a tool round. Explicit method and limit
  reasons remain covered in their separate examples.

- A completed request retains available usage, reasoning details, thinking
  trace and final thinking text. `ask_sync` and `await` keep their result tuples.
- Each thinking trace entry has the actual call ID and model-call number.
  Tool rounds and typed-output repair retain the entries from each model call.
- A final response without thinking removes `last_thinking`. Earlier thinking
  stays in the trace. The most recent non-empty reasoning details remain
  available within that request.
- A second request on the same Agent starts without optional response metadata.
  Earlier conversation data cannot fill the new request's metadata.
- Empty and invalid optional provider fields are omitted. Streamed thinking
  stays separate from answer text. Model completion events expose normalized
  tool-call maps, ordered content parts and the available response metadata.
- A later provider failure or cancellation retains metadata from completed
  model calls. The terminal event has the same metadata as the committed record.
- The snapshot completion helper retains its source order. Details take
  precedence over result-map fallbacks. An explicit empty usage map suppresses
  that fallback. Empty reasoning details permit a search for the latest assistant
  with non-empty reasoning data. Explicit metadata overrides derived values.
  Unrelated request metadata remains present.

`Jido.AI.Request.Metadata` contains the existing snapshot extraction code and
one model-turn reducer. Both the Flow result and session event owner use that
reducer. The session owner can therefore retain completed-call data when a
later operation fails. No additional runtime process or model loop was added.

This is partial evidence for PR 233. It covers the basic live ReAct path and
the pure snapshot helper. Other reasoning methods, standalone execution,
transformer thinking-state parity, partial interrupted thinking, completed tool
outputs and durable recovery still need their own checks. The mock covers one
provider wire format. The root package now uses local v3 dependencies; its full test and release gates remain open.
