# Anatomy of an AI turn

An AI request can last much longer than the Jido Turn that admits it. This is
the key runtime distinction. `ask/3` sends a routed Signal. AgentServer admits
the request and commits a request record. The AI Coordinator owns the live
request after admission; Jido Flow runs the model and tool steps. A final
Signal settles the request and commits the accepted result through
AgentServer. The caller can await the same request handle throughout.

```text
Caller             AgentServer          AI Coordinator / Flow       Model / Tool
  | ask(query)          |                         |                        |
  |-------------------> | admit + record pending  |                        |
  | <--- request handle | ---- start request ----> |                        |
  |                     |                         | context -> model ----> |
  |                     |                         | <--- tool choice ------ |
  |                     |                         | validate/run tool ---> |
  |                     |                         | <--- tool result ------ |
  |                     |                         | next model call -----> |
  |                     | <--- settle result ----- | <--- final answer ----- |
  |                     | validate + commit       |                        |
  | <--- await result -- |                         |                        |
```

The diagram is one request, not one uninterrupted AgentServer callback.
AgentServer can commit other accepted domain work while the model is running.
The final commit must reconcile with the current Agent state. The request
handle identifies the AI work; the AgentServer PID identifies the live Agent;
the Session and Thread values carry portable conversation data.

Context assembly selects prior completed conversation entries. Tool calls and
their outputs join the active request Context. The runtime does not promote
pending or failed user input into the default completed Context. Streaming
events are observations of progress, not a second state store. An observer
can miss events and still read committed request state later.

Read [request lifecycle](../../examples/02_requests/02_01_session/README.md)
and [inspection](../../examples/02_requests/02_22_request_inspection/README.md)
with this diagram. Then read [long-running turns](10_long_running_turns.md) for
ownership and time limits.
