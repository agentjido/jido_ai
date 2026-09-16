# Orchestration ownership and migration

`Jido.Session` remains the portable interaction value. Its module name and data
format do not change. The value files now live at `lib/jido_session.ex`,
`lib/jido_thread.ex`, and `lib/jido_thread/entry.ex`.

Replace `Jido.AI.Session` calls and aliases with `Jido.AI.Orchestration`.
Its child modules use the same new namespace, except `Session.Runtime`, which
is now `Orchestration.Coordinator`. No compatibility wrapper is retained.
The later runtime refinement uses one request lifecycle. `ask` always returns
a handle; `ask_sync` waits for settlement. Core route helpers return admission.
Internal routes now use `jido.ai.request.*`. Rebuild older stored Agent Codec
documents. See [the current migration table](public-api-map.md#migration-from-the-previous-v3-draft).

## Boundaries

- Session and Thread hold portable interaction data.
- Request identifies one unit of work and provides result access.
- Orchestration owns admission, cancellation, delivery, and ordered commits.
- Execution runs one prepared model/tool/reasoning Flow through core Exec.
- Configuration owns portable overrides; Observe owns event values.
- Core Jido owns Agent instances, child lifecycle, routing, and topology.

## Delegation design constraints

Delegation is future work, not a feature added by this rename. Represent it as
linked requests to addressable Agents. Keep the topology relationship (child
or peer) separate from the request relationship (delegator and delegate).

Transfer context explicitly. Each receiving Agent owns its commits; the parent
decides which result enters its Thread. Preserve request correlation, define
cancellation and late-result policies, and bound deadlines, depth, and resource
use. Cancelling work on a peer must not implicitly stop that peer. Reuse core
Jido lifecycle and routing contracts rather than adding another process manager.
