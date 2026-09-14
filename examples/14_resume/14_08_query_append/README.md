# 14_08: Native query append and State counters

[Example](agent.ex) and
[tests](../../../test/examples/14_resume/14_08_query_append/14_08_query_append_test.exs) use the public
standalone API, its native Agent and Session, real tools and the shared MockLLM.
These example tests are excluded by default.

## Continue a conversation

`ReAct.continue(token, config, query: query, context: context, limits: limits)`
accepts non-empty text or a content-part list. `stream_from_state/3` accepts
the same option. Omitted, nil, empty-string and other non-list/non-string values
retain the old no-append behavior. A terminal token without appended input
returns its saved result without model work.

An initial State can add input before its first model call. A native model or
tool checkpoint can add input to the saved run. A newly completed native run
also retains continuation data. The next model sees prior user, assistant and
tool entries once. Request/run identity, sequence, usage, call counters and
committed domain state survive. There is one system instruction message.

When the saved response has pending tools, the runtime finishes that tool round
before it adds the new query to model history. This preserves a complete tool
exchange. Appended input remains portable pending data until those tools finish.
It does not bypass tool permissions or create an input-injection event.
This fixes the old append path that reset status and could skip pending tools.

The new input consumes the remaining reasoning and model limits. It does not
reset total tool calls or remaining execution time. A larger timeout supplied
on resume cannot extend the saved bound. New output validation starts with
fresh repair state, while previous model calls still count against the run's
model limit. The old append path did not advance its iteration for a new final
answer; v3 uses the same finite request budget as active queued input.

## One checkpoint format

Native checkpoint data version 2 adds `before_llm` and `terminal` positions to
`after_llm` and `after_tools`. The token envelope remains `rt2`, payload version
2; the outer State remains version 3. These version numbers name different
formats.

Terminal success retains the same native checkpoint structure. Its domain
state reflects the committed Agent and its pending-effects list is empty.
Appending input therefore retains domain changes without applying old effects
again. The internal transfer field is removed from public stream event data;
the signed checkpoint token is the public continuation value.

Native checkpoint data uses version 2. Unsupported versions, inconsistent
outer/native counters, and non-user pending queries are rejected.

| Saved position | State iteration |
| --- | --- |
| Before a model call | Completed reasoning iterations plus one |
| After a model response | Current reasoning iteration |
| After a complete tool round | Next reasoning iteration |
| Successful final answer | Current reasoning iteration |
| Maximum-iteration result | Next iteration that could not execute |

`runtime.model_calls` remains separate. Model-based output repair increases
model calls without increasing reasoning iteration. Native model events retain
their model-call counter. State no longer derives its reasoning position from
that counter. The examples prove this through repair, tool resume and append.

## Real boundaries and limits

A rich initial-State append sends text and an uploaded file ID through buffered
OpenAI Responses encoding. That provider path supports PDF file references.
The initial fixture used buffered Chat Completions, which ReqLLM rejects for
PDF attachments; it was corrected to the supported wire format. No live model
service is used.

Run from the repository root:

```sh
mix test --include example --seed 0 test/examples/14_resume/14_08_query_append/14_08_query_append_test.exs test/examples/14_resume/14_03_checkpoint_resume/14_03_checkpoint_resume_test.exs test/examples/14_resume/14_06_trace_and_cycles/14_06_trace_and_cycles_test.exs test/examples/14_resume/14_07_standalone_input/14_07_standalone_input_test.exs
```

See the [implementation record](../../../docs/v3-spike/implementation.md) for
design history. Restart after failure or cancellation is not supported. Tokens
remain caller-owned and replayable; this does not prove durable exactly-once
work. Parent inspection, context lanes and compaction, provider variants, and
durable recovery are outside this example.
