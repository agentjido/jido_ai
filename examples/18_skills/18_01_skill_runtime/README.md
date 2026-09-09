# 18_01: Skill activation and resource access

[Agents and provider](agent.ex) and
[27 example cases](../../../test/examples/18_skills/18_01_skill_runtime/18_01_skill_runtime_test.exs)
run the real skill Actions through Session, core Flow and the shared HTTP mock.
The public Agent and native AI DSL use the same runtime.

## Host binding

The host prepares a catalogue with `Jido.AI.Skill.AgentIntegration.prepare/1`
and adds its `tool_context` fields to the trusted request context. The example
uses explicit loading tools. This low-level path remains available.
[18_02](../18_02_skill_authoring/README.md) adds `agent_skills`, automatic tools/index
setup and the native `skills` block. Compilation and static definition
validation do not read the filesystem.

```elixir
integration = Jido.AI.Skill.AgentIntegration.prepare!(
  specs: [%Jido.AI.Skill.Spec{
    name: "review",
    description: "Review a document.",
    body_ref: {:inline, "Check each claim against its source."}
  }],
  resource_provider: {MyApp.SkillResources, :handle}
)

context = Map.merge(host_context, integration.tool_context)
{:ok, request} = MyAgent.ask(server, "Review this case", context: context)
```

A request's `tool_context` option cannot set the reserved catalogue, provider
or policy keys, in atom or string form. It returns an error before admission.
Use the trusted host context for those fields. Signal data cannot select them.
A supplied empty or invalid catalogue remains closed; it cannot fall back to
the global Registry. The public unscoped Action API still supports that Registry.

## Ownership and restore

A skill session is scoped to the Session runtime PID, AI profile and a digest
of the host catalogue/provider/policy binding. Tool workers share that identity.
An explicit host binding change gets a new activation scope. A request-level
session ID cannot replace the native scope. Existing activations remain live
until explicit cleanup or owner exit; a model failure does not clear them.
No PID, provider closure or activation handle enters portable Agent state.

The existing Registry monitors live owners and removes their activation scopes
on exit. Cleanup of one Agent does not clear another Agent. Lazy Registry
startup is unlinked from the first caller. Concurrent registration keeps the
first activation context. This does not make provider callbacks exactly once:
concurrent activation work can still call a provider more than once.

After restore, committed instructions remain in history. Resource handles do
not. The host must bind the catalogue and activate again before resource access.
Explicit `Activation.clear/1` follows the same rule. It does not erase committed
instructions. Repeated activation retains complete tool-call/result pairs; it
does not deduplicate instruction text by skill name.

## Trusted tool history

Durable refs require the concrete `LoadSkill` Action, the public `load_skill`
name, a successful original payload and a successful approved payload. Both
payloads must have the same string skill name and string instructions. A host
callback can change the approved instructions. Renaming, failed activation,
failed callbacks and a different Action named `load_skill` cannot create trusted
refs. User refs cannot add skill durability to user or tool history.

Session commits the approved result and its refs. The Agent-owned session thread keeps
them. Compaction preserves its matching assistant call and actual instructions;
the next captured HTTP request contains them. Direct host-imported history
remains a trusted host operation, as defined in
[02_23](../../02_requests/02_23_context_operations/README.md). This is not a cryptographic provenance
format or a permission to load resources after restore.

## Resources and provider transport

Existing discovery, strict/lazy loading, module and runtime Specs, diagnostics,
policy bounds, Registry and resource-provider APIs now compile against v3.
The Actions retain their category/tags/version functions and normalize known
string input fields before core schema validation. The v3 direct execution
entry point is `Jido.Exec.run/3`; removed `Jido.Action.Tool` calls were transferred.

The examples prove current filesystem body loading, relative paths and rejected
escape paths. Runtime providers receive opaque IDs and current request context.
Unlisted IDs fail before a provider call. Provider failures become tool errors.
Resource policy validates the returned content before model transport.

Images use the mock's Chat endpoint. PDFs use its Responses endpoint because
the Chat provider rejects PDF attachments. Captured requests contain the actual
base64 attachment bytes. The default resource policy rejects binary content.
One shared mock serves both formats; no skill-specific model client was added.

## Evidence and remaining work

The 27 new example cases pass. A separate command passes 293 retained
skill/resource tests from the root suite against the v3 build. That command
omits the four installed-application checks in `runtime_contracts_test.exs`
and the skill CLI test file. They require package/CLI validation and remain open.
They were not counted as passing or added to the default example suite.

History links add partial evidence for PRs 286, 316, 325, 353, 354, 358 and 360.
All release/history statuses remain pending. Automatic skills authoring,
standalone skill continuation, full old-Agent conversion, packaged resources,
CLI, provider variants, complete failure/recovery, the minimum runtime and root
package/consumer/migration/rollback gates remain required.
