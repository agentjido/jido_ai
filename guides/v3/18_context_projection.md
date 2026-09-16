# How Context is built

The model receives a projection, not the raw Thread. The projection selects
the active Context lane, applies replacement operations, and keeps completed
conversation entries in order. It ignores application entries that are not AI
messages. It also omits an incomplete tool exchange rather than inventing a
missing tool result. References stay on Thread entries outside the provider
message body.

`memory history: :messages` tells the profile where to find the Session.
Without this declaration, retaining request records does not mean retaining
conversation Context. The next request may start without earlier messages.
With memory, a successful request can add its user input, tool exchanges, and
final answer to the selected Context.

There are two useful views for a failed request. Raw Thread evidence can show
what was attempted. The default selected Context excludes pending or failed
input that was not successfully settled. This prevents a later model call
from treating failed work as completed conversation. Inspect both views when
you debug a failure; do not delete raw evidence to make the Context clean.

The public `Jido.AI.Thread.Projection.select/1` returns a selected Thread.
`Jido.AI.Thread.Projection.messages/1` returns provider-compatible messages.
Use these APIs for an application display or test. Do not copy projection
rules into an application-specific `history` list. Validate imported Session
data before it becomes model input.

The [Thread value example](../../examples/02_requests/02_27_thread_session_values/README.md)
tests encoding and complete tool exchanges. Continue with [multiple
Contexts](19_multiple_contexts.md).
