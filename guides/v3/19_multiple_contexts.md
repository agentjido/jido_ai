# Multiple Contexts

One Session can hold several named Context lanes. A lane reference selects
which completed conversation the next request sees. This is useful when one
Agent must work on two cases without mixing their histories. The Agent
identity and Session remain the same; the selected Context changes.

Use `Jido.AI.Orchestration.modify_context/3` to replace a lane with a
validated `Jido.Thread` or to switch to an existing lane:

```elixir
{:ok, _agent} =
  Jido.AI.Orchestration.modify_context(server,
    %{type: :replace, result_context: saved_thread},
    context_ref: "case-a",
    op_id: "load-case-a"
  )

{:ok, _agent} =
  Jido.AI.Orchestration.modify_context(server,
    %{type: :switch},
    context_ref: "case-a",
    op_id: "select-case-a"
  )
```

Give each operation a stable `op_id` when callers may retry it. Repeating an
applied ID is idempotent. A change requested while AI work is active can be
deferred until that request settles. Do not assume a switch changes the
messages of a model call already in progress. Check the active reference and
selected projection after settlement before you send the next question.

A replacement is not a license to insert arbitrary chat-shaped maps. Build a
valid portable Thread, preserve complete tool exchanges, and avoid putting
secrets in content. A lane is a Context selection mechanism, not another
AgentServer or a separate worker process.

Run [Switch Context](../livebooks/switch_context.livemd) with two saved
Threads. Continue with [checkpoint and resume](20_checkpoint_resume.md).
