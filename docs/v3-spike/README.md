# Jido AI v3 migration

Status: migration started on 2026-09-06. Authoring, shared operations and session requests have production ports and acceptance examples; the full package port is in progress.
Initial inspection: 2026-09-05. Migration planning update: 2026-09-06.

Use examples to select the API and execution model. Keep current AI features in
the port map. Use Jido v3 Actions, Flows, and Plugins for their execution.

- [Migration plan](migration-plan.md): the complete v2-to-v3 port, with DSL authoring first.
- [Example catalog](examples.md): proposed examples and acceptance checks.
- [Unified Agent DSL plan](agent-dsl.md): canonical authoring, the full Jidoka-derived example, lowering and acceptance requirements.
- [V3 acceptance project](../../examples/v3/README.md): local foundation examples and one mock LLM server.
- [Feature port map](feature-map.md): current features, proposed destinations,
  and source evidence.
- [Public API map](public-api-map.md): entry points, generated wrappers and
  API acceptance cases; declared-source inventory for all production files.
- [Commit and PR audit](history-audit.md): every post-2.0 commit, user feedback,
  regression examples and required migration evidence.

The migration goal now includes three preparation passes, the complete
post-2.0 history audit, and four later refinement/simplification checkpoints. See the
[preparation results](migration-plan.md#preparation-three-refinement-passes)
and [example priorities](examples.md#implementation-priorities).
The user authorized production implementation with “start the migration”. See the [implementation record](implementation.md) for current checks and remaining work.

The history pass is complete: 126 commits after `v2.0.0` through `fc5bc143`,
plus all 103 linked merged PRs, have source reviews and required acceptance
cases. User reports and PR feedback supply regression cases inside the existing
18 example families. Historical features have partial execution evidence;
all 126 row-level port checks remain pending until their full gates pass.


## Source baseline

The new `jido_ai` branch is `v3-spike`. It starts at
`fc5bc1434ddb69493fe8a68443f03bc6a198c5a2`, the fetched `origin/main` tip.
The previous local `main` was eight commits behind, at `38fa3f62`.

| Package | Local target | Observed commit | Declared version |
| --- | --- | --- | --- |
| jido_ai | This repository, `v3-spike` | `fc5bc143` | 2.3.0 |
| jido | `../jido`, `v3-spike` | `b770efa7` | 2.3.3 |
| jido_action | `../jido_action`, `release/v3` | `83e0b8c` | 3.0.0-beta.7 |
| jido_signal | `../jido_signal`, `release/v3` | `5a09b6bc` | 3.0.0-beta.4 |

The table records the initial inspection. Core then advanced to `fb9da00f`
and has further local changes during the acceptance work. The example project
README records the later test baseline. The production port added the generic
Agent extension contract described in the implementation record.
The `jido_v3` directory is the donor repository;
the intended dependency is `../jido`.

The root dependencies still select v2. Production code is being ported in the
root source tree. The separate v3 example project compiles those new authoring,
operation, shared-helper and session modules directly. It also supplies the
acceptance fixtures and shared mock. The root package has not yet passed a v3
compile. See the implementation record for current checks.
The source findings below describe the initial inspection, not a completed
package upgrade. No live provider call is required by the example project.

## Dependency change to make when implementation starts

Use a path dependency on `../jido`. A path selects the working directory,
including later uncommitted changes; it does not pin the commit in the table.
Record the target commit and working state for each acceptance run.

The current direct `jido_action ~> 2.3` requirement must also change. Core now
requires `jido_action ~> 3.0.0-beta.7` and `jido_signal ~> 3.0.0-beta.4`.
Use local path overrides for these packages when testing the whole local stack.
The sketch below is a future edit, not an applied change:

```elixir
{:jido, path: "../jido"},
{:jido_action, path: "../jido_action", override: true},
{:jido_signal, path: "../jido_signal", override: true}
```

Check the resolved ReqLLM version at the same time. AI declares `~> 1.14`;
core declares optional `~> 1.21`. Do not copy the old lockfile unchanged and
assume the dependency set is valid. Keep this local setup separate from the
eventual published dependency requirements.

## Main findings

1. Core removed `Jido.Agent.Strategy`, command hooks, StateOps, the old Server
   State struct, and the `DirectiveExec` protocol. Current AI code uses all of
   them. Changing the dependency alone cannot complete the port.
2. One Signal now selects one Action or Flow. A successful direct command
   returns `{:ok, candidate, directives}`. A live Turn validates and commits
   the complete candidate state. The Flow can call models and tools before
   this commit. A later failure does not undo completed external work.
3. Core already has ten useful LLM examples: model response, history, tool
   call, tool loop, parallel tools, grounded answer, output repair, compaction,
   child delegation, and recursive analysis. Reuse their acceptance patterns;
   add the AI provider, policy, and result contracts.
4. `Jido.Exec` provides Flow execution, concurrency, cancellation, deadlines,
   and bounded continuations. Step-wise execution is local execution state.
   It is explicitly not a durable checkpoint.
5. AI history, request records, skill activation, and runtime process handles
   need separate ownership. Removing PIDs only when writing a checkpoint is
   too late for a portable v3 Agent state.
6. Spark can support DSL extensions, but core currently calls
   `use Jido.Agent.DSL` without forwarding extension options. Its compiler
   treats every entity under `agent` as a Plugin. An `ai` block requires a
   defined extension contract or explicit lowering before that compiler runs.

Use [the core Agent API](../../../jido/lib/jido/agent.ex)
and source as the API baseline. Documents under core `docs/design` are pending
proposals. In particular, do not assume that the proposed Ref facade, isolated
Plugin preparation, or definition revision checks already exist. Core's
[feature probes](../../../jido/docs/examples/feature-acceptance-results.md)
record these differences. This task did not rerun those probes.

## Proposed execution model

Keep one set of AI operations and reasoning rules. Use two explicit ways to
run them:

| Form | State and completion | Main use |
| --- | --- | --- |
| One bounded Flow | Local intermediate data; one final Agent commit | Chat, extraction, short ReAct, planning, bounded search |
| A session across Turns | Commit request state and pending work; use owned runtime work and correlated completion Signals | Streaming request APIs, steering, interrupts, child work, recovery |

A Flow can emit transient progress while it runs. Streaming alone does not
require several commits. However, normal Signals to the same busy Agent cannot
be assumed to update that active Flow. Steering needs a separate runtime input
path or explicit boundaries between Turns. Prove this before choosing a default.

The session form should run the same model/tool operations in bounded segments.
Do not create a second independent reasoning implementation. Keep durable data
such as request IDs, messages, pending tool IDs, and attempt counts separate
from model clients, stream sinks, tasks, and resource-provider closures.

Use public core APIs. In this snapshot, `AgentServer.call/3` supports transient
context. `cast/2` is best effort; `send_request/3` does not take the same context
options. The current AI `await` implementation uses removed `await_completion`.
Request admission, transient context, and result collection therefore need an
explicit design. A send acknowledgement must not mean that an AI request was
admitted or completed.

## First discussion pass

Start with examples `01` through `06`. These test the largest decisions:
minimal authoring, typed output, tool policy, Flow composition, streaming, and
portable state. Add the remaining examples only after their contracts are clear.

Working preference: keep current feature behavior and make the v3 API the main
authoring interface. Old API support is a separate decision. Do not confuse
feature parity with retention of Strategy structs or private Server fields.

Decisions still open:

- Should ordinary AI Agents default to one Turn or to a session across Turns?
- Should one Agent have one AI profile first, or several named profiles?
- Which old public function names and result shapes must remain?
- Which tool state changes are allowed, and who combines parallel changes?
- Should interrupted Agent requests fail after restore, as they do now, or
  gain a new durable resume contract? Standalone checkpoint tokens are a
  separate existing feature.
- Which small core extension is acceptable for nested `agent do` authoring?

After discussion, write one profile per accepted example. Give it matching
source and test paths, as in core. First prove the plain Action/Flow form.
Then prove that the DSL produces the same behavior. Keep blocked core features
visible in a separate list. No implementation begins from this draft alone.
