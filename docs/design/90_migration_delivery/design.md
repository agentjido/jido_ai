> Target seam design. This document is pending approval.

# Migration, delivery, and consumer support design

## Scope and owner

- Owner: Jido AI release, package metadata, documentation, examples, CLI adapters, test helpers, quality gates, and sibling-package integration.
- In scope: V2 capability disposition, V3-only public formats, removals, package versions, dependency matrix, migration guides, CLI and test support, release checks, and rollback criteria.
- Out of scope: New runtime behavior, compatibility engines, mixed production V2/V3 package sets, and approval of another seam's target contract.

## V2 capability anchor

V2 is the user-capability baseline for the migration. The V3 release retains useful AI behavior and replaces the runtime architecture. A feature is not retained only because a module name remains, and it is not removed only because its V2 implementation used Strategy callbacks.

The release uses five dispositions:

| Disposition | Meaning |
| --- | --- |
| Retain | Keep the public capability and align it with V3 contracts |
| Replace | Keep the user outcome but replace the public or internal contract |
| Move | Put the contract in `jido`, `jido_action`, `jido_signal`, `jido_browser`, or the host |
| Defer | Exclude it from the first stable V3 release with explicit status |
| Remove | Delete the capability or compatibility surface after evidence and migration review |

The V3 policy is:

- Keep the direct `Jido.AI` facade, Profile, Query, Context, Output, Usage, tool bridge, request calls, typed Signals, supported capabilities, skills, and observation surfaces.
- Keep `use Jido.AI.Agent` as the canonical Spark authoring form.
- Replace Strategy behavior, state-operation helpers, execution Directives, private runners, and TaskSupervisor ownership.
- Move graph mechanics to Flow and Exec; move Agent lifecycle and commit to Jido; move Signal transport to Jido Signal; move browser adapters to Jido Browser; move durable services to the host.
- Do not accept V2 option, Signal, state, or checkpoint formats.

## Model

Delivery proceeds through explicit gates:

```text
approved seam designs
  -> alignment evidence and gap closure
  -> public API review
  -> package-local format, compile, and tests
  -> sibling V3 integration matrix
  -> documentation and examples
  -> release candidate
  -> stable release
```

The package version for the stable target is `3.0.0`. Pre-release versions can be used while seam contracts remain incomplete.

Compatibility levels are:

- **Stable:** Documented public V3 API with semantic-version support.
- **Experimental:** Documented but not stable; no compatibility guarantee until promoted.
- **Internal:** Not a public API.
- **Removed:** Absent from the V3 stable package and listed in the migration guide.

## Requirements

### Inventory and removal

`DEL-REQ-001`: Every public V2 module, function, macro, option, Signal, CLI command, and checkpoint form shall have a Retain, Replace, Move, Defer, or Remove disposition before V3 release.

`DEL-REQ-002`: Each retained or replaced V2 capability shall map to one approved V3 seam owner and one acceptance contract.

`DEL-REQ-003`: The V3 package shall not ship compatibility shims for V2
options, Signals, state, checkpoints, workers, or Strategy behavior.

`DEL-REQ-004`: Each removed public API shall state its V3 replacement or an
explicit no-replacement reason.

`DEL-REQ-005`: Each removed public API shall appear in the migration guide with a replacement or an explicit no-replacement reason.

`DEL-REQ-006`: Experimental methods or capabilities shall be marked in module documentation, guides, and package release notes.

### Package and dependency matrix

`DEL-REQ-007`: The stable package shall declare a V3 package version and compatible released versions of direct dependencies.

`DEL-REQ-008`: Release verification shall use a compatible V3 set of `jido_action`, `jido_signal`, `jido`, `jido_ai`, and applicable integration packages.

`DEL-REQ-009`: A production V3 test shall not select a V2 sibling package.

`DEL-REQ-010`: Local path dependencies used for integration shall be replaced with approved release requirements before publishing unless release policy explicitly permits another source.

`DEL-REQ-011`: Package metadata shall describe Jido AI as the AI integration and behavior layer and shall not claim ownership of generic workflows or durable orchestration.

### Tests and quality gates

`DEL-REQ-012`: Each approved requirement shall have Proven acceptance evidence or an explicit approved deferral before release.

`DEL-REQ-013`: Package release checks shall run formatting, warnings-as-errors compilation, package tests, examples or acceptance tests, documentation generation, and package build.

`DEL-REQ-014`: Release checks shall include boundary tests that reject private AgentServer access, direct Flow runtime access, custom Signal transport, and nonportable state.

`DEL-REQ-015`: Release checks shall cover Turn and session parity, model and tool error paths, resource limits, cancellation races, structured output, Plugin conflicts, codec safety, checkpoint restore, and observation redaction.

`DEL-REQ-016`: A known failing or non-compiling test shall block a stable release unless the related feature is explicitly removed and the test is replaced by approved evidence.

`DEL-REQ-017`: Test helpers shall use public V3 contracts and shall not expose private runtime state as a supported testing technique.

`DEL-REQ-018`: A release candidate shall pass the same required matrix as the stable release.

### Documentation and examples

`DEL-REQ-019`: The package overview shall describe the package boundary, V3 Agent and Flow model, request modes, effect timing, durability limits, and host responsibilities.

`DEL-REQ-020`: Public guides shall use `Jido.AI.Agent` and its Spark DSL as the
primary authoring form. Direct core Agents shall use `Jido.AI.DSL` explicitly.

`DEL-REQ-021`: Examples shall include direct generation, Turn mode, session mode, streaming, tools, structured output, reasoning, retrieval, quota, skills, checkpoints, and observation.

`DEL-REQ-022`: Each example shall state whether it uses a real provider, test provider, external service, in-memory store, or durable host resource.

`DEL-REQ-023`: The migration guide shall show V2-to-V3 mappings for Agent macros, Strategy modules, tools, request calls, Plugins, Signals, skills, and checkpoints.

`DEL-REQ-024`: Documentation shall not present old guides, old source, or migration notes as canonical V3 behavior.

### CLI and consumer support

`DEL-REQ-025`: CLI adapters shall call public V3 Profile, request, stream, inspection, and cancellation APIs.

`DEL-REQ-026`: CLI output shall use safe observation and result views and shall not print credentials, hidden reasoning, or raw provider responses by default.

`DEL-REQ-027`: Consumer test helpers shall provide deterministic model, stream, tool, clock, and registry doubles through public dependency-injection points.

`DEL-REQ-028`: A test helper shall not start an application store or runtime process implicitly unless its function name and documentation state that behavior.

### Release and rollback

`DEL-REQ-029`: Release notes shall list stable, experimental, deferred, and removed surfaces.

`DEL-REQ-030`: Before stable release, every seam shall have an approved design, complete alignment state, and no unresolved conflict.

`DEL-REQ-031`: A publish rollback procedure shall identify how to yank or supersede a bad release without changing already published artifacts.

`DEL-REQ-032`: A release shall not claim durable orchestration, exactly-once effects, or provider-independent behavior beyond the approved contracts.

## Public contract

The release artifact set is:

```text
README and package overview
API documentation
V2-to-V3 migration guide
capability support matrix
dependency compatibility matrix
examples and test-provider setup
CHANGELOG and release notes
package archive and checksum
```

Recommended first-release compatibility table:

| Surface | V3 status |
| --- | --- |
| `Jido.AI` direct facade | Stable |
| Core Agent DSL plus `Jido.AI.DSL` | Stable |
| `Jido.AI.Profile` and portable authoring | Stable |
| `use Jido.AI.Agent` | Stable V3 authoring |
| Query, Context, Turn, Output, Usage, Error | Stable after seam 01 approval |
| ReAct, Chain-of-Thought, Chain-of-Draft, Adaptive | Stable after seam 05 approval |
| Other reasoning methods | Experimental unless promoted |
| Request, stream, cancel, and steering APIs | Stable after seam 07 approval |
| Retrieval and quota in-memory stores | Supported nondurable adapters |
| Skills | Stable after seam 09 approval |
| V2 Strategy behavior and worker APIs | Removed |
| Package TaskSupervisor | Removed |
| V2 checkpoint import | Removed |

The exact table is pending seam approval and alignment evidence.

## Invariants

- `DEL-INV-001`: Each shipped public capability has one approved seam owner.
- `DEL-INV-002`: No V2 compatibility shim or data decoder ships in V3.
- `DEL-INV-003`: Stable release tests use one compatible V3 package set.
- `DEL-INV-004`: Known non-compiling tests block release unless their feature is explicitly removed.
- `DEL-INV-005`: Documentation distinguishes stable, experimental, deferred, and removed surfaces.
- `DEL-INV-006`: Test and CLI helpers use public contracts.
- `DEL-INV-007`: Published artifacts are immutable.
- `DEL-INV-008`: Release claims do not exceed proved behavior.

## Downstream guarantees

| Consumer | Guaranteed contract |
| --- | --- |
| Existing V2 users | Complete disposition and migration guidance |
| New V3 users | One primary Agent DSL and Profile authoring path |
| Package maintainers | Requirement-linked release gates and dependency matrix |
| Integration packages | Explicit V3 versions and ownership boundaries |
| Host applications | Clear runtime resource, durability, and operational duties |

## Open design decisions

| ID | Question | Recommended option | Effect |
| --- | --- | --- | --- |
| `DEL-DEC-001` | What V2 source compatibility is required? | None | Gives V3 one authoring and data contract |
| `DEL-DEC-002` | Which reasoning methods are stable? | Use the seam 05 recommended first-release set | Bounds testing and compatibility |
| `DEL-DEC-003` | Does the first V3 release include CLI support? | Yes, for authoring inspection, request execution, streaming, and cancellation | Preserves practical V2 workflows |
| `DEL-DEC-004` | What is the stable release test gate? | All package tests, acceptance examples, docs, package build, and V3 sibling matrix pass | Makes release readiness measurable |
| `DEL-DEC-005` | Is the V2 checkpoint importer required? | No | Keeps checkpoint restore limited to V3 data |
