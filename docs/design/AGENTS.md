# Jido AI design documentation instructions

Adapted from `jido/docs/design/AGENTS.md`.

These instructions apply to all files in `docs/design`.

## Review status

The **Document review status** table in `README.md` is the source of truth for
user approval. Design maturity labels such as `Proposal`, `Implemented in Jido AI`, or `Proposed decision` do not mean that the user approved a document.

Use only these review values:

- `Pending approval`
- `Approved`

When an agent changes a design document, the agent must set that document's
row to `Pending approval` before it finishes the task. This rule applies to all
changes, including small editorial changes.

When an agent adds a design document, the agent must add it to the table with
`Pending approval`.

An agent must not set a document to `Approved` unless the user explicitly
names that document as approved. Do not infer approval from general positive
feedback or from a request to continue.

Changing only the review-status table does not reset the review status of
`README.md`. Any other agent change to `README.md` resets its row to `Pending
approval`.

## EARS requirements

Use EARS, the Easy Approach to Requirements Syntax, when a design document
specifies required behavior. This rule applies to target contracts, alignment
plans, acceptance matrices, migration gates, and approved invariants.

Use one of these forms:

```text
<SEAM>-REQ-<number>: The <owner> shall <required response>.
<SEAM>-REQ-<number>: When <trigger>, the <owner> shall <required response>.
<SEAM>-REQ-<number>: While <state>, the <owner> shall <required response>.
<SEAM>-REQ-<number>: If <unwanted condition>, then the <owner> shall <required response>.
<SEAM>-REQ-<number>: Where <feature is enabled>, the <owner> shall <required response>.
<SEAM>-REQ-<number>: Where <feature>, while <state>, when <trigger>, the <owner> shall <required response>.
```

Use the combined form only when a simple form cannot state the requirement.

Follow these rules:

1. Give each requirement one stable and unique identifier.
2. Use one observable behavior in each requirement.
3. Name the Jido component that owns the response.
4. Use `shall` only for required target behavior.
5. Keep current facts, recommendations, and approved requirements separate.
6. Define vague terms with measurable limits or remove them.
7. Link each requirement to current evidence or a required acceptance test.
8. Keep requirement identifiers stable when wording changes. Retire an
   identifier instead of assigning it to a different behavior.

These examples show syntax only. They are not approved decisions:

```text
AGT-REQ-001: The Agent shall include Plugin-owned state in its complete state map.
TURN-REQ-001: When Turn evaluation selects an executable, the Turn evaluator shall use that executable for the complete Turn.
PERS-REQ-001: If a compare-and-swap result is indeterminate, then the Agent Server shall stop further persistent writes.
```

EARS syntax does not grant approval. Apply the review-status rules in this
file.

## Alignment dependency order

Use this graph when you prepare alignment documents. An arrow points from a
prerequisite seam to a seam that depends on it. Finalize the required
contracts in the prerequisite seam before you finalize the dependent seam.

```mermaid
flowchart TB
    S00["00 Package boundary and invariants"]
    S01["01 Canonical interaction and AI values"]
    S02["02 Model integration and request preparation"]
    S03["03 Tools, sources, and effect policy"]
    S04["04 Shared AI execution"]
    S05["05 Reasoning and planning methods"]
    S06["06 Core runtime and Signal integration"]
    S07["07 Request orchestration and active input"]
    S08["08 Capabilities and policy"]
    S09["09 Skills and resources"]
    S10["10 Authoring and portable definitions"]
    S11["11 Checkpoints and resume"]
    S12["12 Observation and diagnostics"]
    S90["90 Migration and delivery"]

    S00 --> S01
    S00 --> S06
    S01 --> S02
    S01 --> S03
    S01 --> S06
    S02 --> S04
    S03 --> S04
    S04 --> S05
    S04 --> S06
    S05 --> S07
    S06 --> S07
    S02 --> S08
    S03 --> S08
    S05 --> S08
    S07 --> S08
    S03 --> S09
    S06 --> S09
    S07 --> S09
    S05 --> S10
    S08 --> S10
    S09 --> S10
    S04 --> S11
    S07 --> S11
    S09 --> S11
    S10 --> S12
    S11 --> S12
    S12 --> S90

    classDef foundation fill:#e8f0fe,stroke:#315aa6,color:#10254d
    classDef execution fill:#e6f4ea,stroke:#287a3d,color:#143d20
    classDef composition fill:#fff4d6,stroke:#9a6b00,color:#4d3500
    classDef delivery fill:#fce8e6,stroke:#a63b32,color:#551b17

    class S00,S01 foundation
    class S02,S03,S04,S05,S06,S07 execution
    class S08,S09,S10,S11,S12 composition
    class S90 delivery
```

This graph defines the minimum planning gates. It does not list every code
dependency. A seam can refer to a later seam, but it must not decide the later
seam's owned contract.

Each alignment document must:

1. Read the canonical code, the seam design, and the seam's gap register in `alignment.md`.
2. State which prerequisite alignment documents it used.
3. List unresolved prerequisite decisions as blockers or explicit assumptions.
4. Define an ordered plan to move from current behavior to the approved design.
5. Preserve current public behavior unless the plan includes a clear migration.
6. Define tests or other evidence for each alignment step.

## Seam document pattern

Follow [the seam template](SEAM_TEMPLATE.md). Each seam has three documents by
default:

- `README.md` is the short briefing and review entry point.
- `design.md` contains the target contract and EARS requirements.
- `alignment.md` contains current evidence, the gap register, the ordered plan,
  migration work, and the acceptance matrix.

Do not create separate `briefing.md`, `gap-analysis.md`, or `evidence.md` files.
Fold that content into the three standard documents. A supporting topic
document is permitted only when it defines a large independent contract.

Put each fact in one place. Link to it from the other documents. Keep the
briefing at 1,200 words or less. The briefing must not introduce a contract
that is absent from `design.md`. The alignment plan must not treat a briefing
recommendation as approved.

Each seam README must contain a `Major gaps and work remaining` section. Keep
this section short. State outcomes and owner seams. Do not list implementation
tasks.

The alignment document can define high-level work packages and dependency
gates. It must not become the formal implementation plan. Create that plan
only after the user approves the seam intent and requirements. Use a named
planning skill only when the user explicitly requests it.

Add each new document to the main review-status table with `Pending approval`.
Keep current facts, recommended decisions, and approved decisions distinct.

Do not prepare dependent seams fully in parallel. Work in graph order. If a
prerequisite alignment changes, review each dependent alignment again.

## Jido AI evidence and scope rules

- Current `lib/` source and executable tests define implemented behavior.
  Record the branch, commit, and any uncommitted source changes in an alignment
  review. A commit alone does not identify a dirty worktree.
- Examples show specific supported authoring behavior. Link their tests and
  state proof limits. Do not infer complete conformance from one passing example.
- Preserve advanced proposals, requirement IDs, and unique design rationale.
  Missing implementation is not permission to remove a capability.
- Separate current facts, target requirements, and decisions. Use the evidence
  states in `README.md`; approval and implementation status are different.
- Keep `Jido.Session`, `Jido.Thread`, and `Jido.Thread.Entry` in this package.
  They are values. `Jido.AI.Orchestration` owns live request coordination;
  its Coordinator keeps process lifetime and ordered commit work together.
- Core Jido owns Agent topology and child lifecycle. AI delegation design
  describes linked work, context transfer, and result policy above that boundary.
- Use `ARCHITECTURE.md` for the high-level current module and seam map.
  Put detailed current evidence and gaps in the owning seam's `alignment.md`.
- The older `architecture-seams.md` is retained research, not current evidence.
  Its proposals remain available for review.
- During a documentation-only task, do not change Elixir, dependencies, examples,
  tests, or package metadata. Record required changes as alignment gaps.
- Validate local links, review-table coverage, seam-map coverage, and identifier
  preservation after documentation edits. Do not report tests as rerun unless
  they were actually run.
