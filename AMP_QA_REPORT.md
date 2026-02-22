# Jido.AI v2.0.0-beta — Documentation QA Report

> Generated: 2026-02-22
> Scope: Evaluate guides, README, and module docs against DOCS_MANIFESTO.md before beta release
> Status: **All steps implemented** ✅

---

## Overall Assessment

The documentation is **already strong** — well above average for Elixir libraries. Guides follow Manifesto principles (problem-aware openings, "you"-addressed, failure modes, defaults). The main gaps are **undocumented public features** and some structural tightening.

### What's Working Well

- README follows the Manifesto funnel (headline → after-state → ecosystem fit → quickstart)
- Guides open with "You want…" / "After this guide…" — textbook Manifesto law #7/#10
- Specificity is strong: exact signal names, default values, deterministic result shapes
- "Failure modes" + "Defaults you should know" sections are high-leverage and match real debugging needs

---

## Step 1: New Guide — Standalone ReAct Runtime (checkpoint + resume)

**Priority:** 🔴 High
**Effort:** Medium (1–3h)
**Type:** Add

### Problem

`Jido.AI.Reasoning.ReAct` exposes a full public runtime API — `start/3`, `stream/3`, `collect/3`, `continue/3`, `cancel/3` — with checkpoint tokens and resumption semantics. **No guide documents this.** Developers won't discover it.

### Deliverable

Create `guides/user/standalone_react_runtime.md` covering:

- [ ] When to use standalone ReAct vs `Jido.AI.Agent` vs `CallWithTools`
- [ ] Copy-paste example: start a run, persist `checkpoint_token`, resume later, collect terminal result
- [ ] Cancel token semantics
- [ ] What event stream items look like / how to build a collector UI
- [ ] Add a row in the README "Choose Your Integration Surface" table pointing here

### Acceptance Criteria

- Guide is runnable end-to-end in a fresh Mix project with Hex deps
- README integration surface table includes "Streaming + checkpoint/resume" → `Jido.AI.Reasoning.ReAct`

---

## Step 2: New Guide — Turn Normalization & Tool Results

**Priority:** 🔴 High
**Effort:** Medium (1–3h)
**Type:** Add

### Problem

`Jido.AI.Turn` is central to response normalization, tool execution helpers, and message projection — but only mentioned in passing (thread guide references `Turn.extract_text/1`). Anyone building custom orchestration flows with `ReqLLM` + tools needs this.

### Deliverable

Create `guides/user/turn_and_tool_results.md` covering:

- [ ] `Turn.from_response/2` — normalizing raw provider responses
- [ ] `Turn.needs_tools?/1` — detecting tool call requests
- [ ] `Turn.execute/4` / `execute_module/4` — running tools from a turn
- [ ] Projecting tool messages for follow-up LLM calls
- [ ] How `Turn.run_tools` fits with `CallWithTools` loops
- [ ] Telemetry hooks around tool execution

### Acceptance Criteria

- Guide includes at least one complete custom orchestration example
- Cross-linked from `tool_calling_with_actions.md` and `thread_context_and_message_projection.md`

---

## Step 3: Restructure `plugins_and_actions_composition.md`

**Priority:** 🟡 Medium
**Effort:** Medium (1–2h)
**Type:** Modify

### Problem

The guide is excellent as a spec but too reference-heavy. It reads like a contract dump rather than a narrative, violating Manifesto law #3 ("each sentence gets the next read").

### Deliverable

Restructure into two parts:

- [ ] **Part 1: "Pick your extension surface"** — 2–3 motivating scenarios (story-driven), helping developers decide between plugins, actions, and strategies
- [ ] **Part 2: "Contracts & defaults"** — current content reorganized as reference material
- [ ] Ensure the first 30% reads like a story, not a spec

### Acceptance Criteria

- A new developer can read Part 1 and know which extension surface to use without reading Part 2
- Part 2 remains comprehensive for implementers

---

## Step 4: Promote Retrieval + ReAct Gotcha

**Priority:** 🟡 Medium
**Effort:** Small (<1h)
**Type:** Modify

### Problem

`retrieval_and_quota.md` documents that retrieval enrichment **doesn't run on `ai.react.query`** — but this critical constraint is buried. Developers will enable retrieval, wonder why their ReAct agent ignores memory, and file issues.

### Deliverable

- [ ] Move the constraint to the top of the guide as a named, highlighted gotcha
- [ ] Frame it with "conversation in their head" tone: _"You enabled retrieval but your ReAct agent ignores memory. Here's why."_
- [ ] Add a brief mention in `first_react_agent.md` linking to this gotcha

### Acceptance Criteria

- The constraint is visible within the first screen of the retrieval guide
- Cross-linked from the ReAct agent guide

---

## Step 5: README Structural Improvements

**Priority:** 🟡 Medium
**Effort:** Small (<1h)
**Type:** Modify

### Problem

README is strong but has structural gaps vs the Manifesto's optimal README architecture.

### Deliverable

- [ ] **Add explicit "Documentation" section** with HexDocs link + agentjido.xyz link (currently buried in "Documentation Map")
- [ ] **Add ReAct runtime row** to "Choose Your Integration Surface" table: "Streaming + checkpoint/resume" → `Jido.AI.Reasoning.ReAct`
- [ ] **Sharpen "Why Jido.AI" bullets** with specific credibility:
  - "Request handles (`ask/await`) prevent concurrent result overwrites"
  - "Stable telemetry event names via `Jido.AI.Observe`"
  - "Policy/quota plugins rewrite unsafe/over-budget requests to `ai.request.error` deterministically"
- [ ] **Add standalone-use clarification** in "Where This Package Fits": _"You can use `jido_ai` without running a Jido agent process via `Jido.AI.generate_*` and `Jido.Exec.run/3`."_

### Acceptance Criteria

- README passes the Manifesto's optimal structure checklist
- All links resolve

---

## Step 6: Document Tool Context Compile-Time Restrictions

**Priority:** 🟡 Medium
**Effort:** Small (<1h)
**Type:** Add

### Problem

`Jido.AI.Agent` implements compile-time safety for `tool_context` AST — rejects function calls, module attributes, pinned vars. Developers hitting this see a compile error with no prior documentation.

### Deliverable

- [ ] Add a "Tool context must be literal data" note + example to `Jido.AI.Agent` moduledoc
- [ ] Add a gotcha entry in `getting_started.md` under common first-run errors
- [ ] Show what fails and what the correct literal form looks like

### Acceptance Criteria

- A developer encountering the compile error can find the explanation in docs within one search

---

## Step 7: De-emphasize / Remove Internal Tooling from Public Docs

**Priority:** 🟡 Medium
**Effort:** Small–Medium
**Type:** Remove / de-emphasize

### Problem

`mix jido_ai.quality` is a contributor/maintainer workflow leaking into the public Hex package surface. The Manifesto explicitly requires separating contributor docs from public docs.

### Deliverable

- [ ] Either:
  - **(A)** Exclude `Mix.Tasks.JidoAi.Quality` from HexDocs output (add to `:skip_modules` or equivalent), OR
  - **(B)** Add clear "Maintainers only" labeling in moduledoc and remove from any user-facing guide listings
- [ ] Audit `cli_workflows.md` to ensure it focuses on user-facing CLI commands only
- [ ] Consolidate "duplicate plugin state key" warnings into one canonical location, link from other guides

### Acceptance Criteria

- External developers browsing HexDocs don't encounter maintainer-only tooling without clear labeling
- Duplicate guidance is consolidated

---

## Step 8: Cross-Package Recipe Stubs (for agentjido.xyz)

**Priority:** 🟣 Low (pre-launch, not pre-beta)
**Effort:** Medium per recipe
**Type:** Add (external site)

### Problem

The Manifesto requires cross-package tutorials on agentjido.xyz, linked from package docs. None exist yet.

### Deliverable

Create recipe stubs or outlines for agentjido.xyz:

- [ ] **Core recipe**: Jido agent + LLM + tools + telemetry (`jido` + `jido_ai` + `req_llm`)
- [ ] **App recipe**: Phoenix LiveView streaming LLM output (`phoenix` + `jido` + `jido_ai`)
- [ ] **Tooling recipe**: Browser-augmented agent loop (`jido_ai` + `jido_browser`)
- [ ] **Background jobs recipe**: Oban + `generate_object/3` for structured extraction
- [ ] Add links to these recipes from the README "Documentation" section once published

### Acceptance Criteria

- Each recipe lists participating packages with hex.pm links
- Each recipe is copy-paste-runnable with Hex deps (no workspace assumptions)

---

## Risks & Guardrails

| Risk | Guardrail |
|------|-----------|
| Docs imply retrieval works for ReAct queries (it doesn't automatically) | Step 4: promote gotcha to top of retrieval guide + cross-link from ReAct guide |
| Too many extension surfaces confuse evaluators (Agent macro vs plugin vs actions vs reasoning runtime) | Step 3 + Step 5: keep integration surface table authoritative, link every row to one guide |
| Internal tooling leaks into public HexDocs | Step 7: exclude or clearly label `mix jido_ai.quality` |
| Guides assume prior context without repeating minimal setup | Each new guide (Steps 1–2) includes a "Prerequisites + copy-paste config" block |

---

## Execution Order

Steps are designed for sequential execution:

1. **Step 1** — Standalone ReAct Runtime guide (highest value gap)
2. **Step 2** — Turn & Tool Results guide (complements Step 1)
3. **Step 3** — Restructure plugins/actions guide (improves existing)
4. **Step 4** — Retrieval + ReAct gotcha (small, high-impact fix)
5. **Step 5** — README improvements (depends on Steps 1–2 for new links)
6. **Step 6** — Tool context restrictions (small addition)
7. **Step 7** — De-emphasize internal tooling (cleanup)
8. **Step 8** — Cross-package recipes (pre-launch, not pre-beta blocker)
