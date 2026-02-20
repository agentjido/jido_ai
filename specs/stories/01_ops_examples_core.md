# Ops + Example Scaffold Stories

### ST-OPS-001 Story Backlog Scaffolding And Traceability
#### Goal
Create a loop-ready backlog scaffold in `specs/stories` with stable story IDs and traceability coverage.
#### Scope
- Create `specs/stories` directory and story files in canonical order.
- Ensure every story card uses the required heading and section contract.
- Ensure traceability matrix has one pipe-table row for every story ID.
- Align `ralph_wiggum_loop.sh` usage examples with actual repository pathing.
#### Acceptance Criteria
- `specs/stories/00_traceability_matrix.md` exists and includes every ST ID.
- Story files `01` through `06` exist with required section headings.
- `rg -n '^### ST-[A-Z]+-[0-9]{3}' specs/stories/*.md` returns all expected IDs.
- Loop usage text references executable path in this repository layout.
#### Stable Test Gate
- `mix test.fast`
#### Docs Gate
- Story docs are plain markdown and parse cleanly in terminal tools.
#### Example Gate
- Story examples in cards reference real repo paths only.
#### Dependencies
- None

### ST-OPS-002 Repo Precommit And Dual Stable Gates
#### Goal
Add a repository-local precommit command and fast stable gate suitable for one-story loop runs.
#### Scope
- Add `precommit` alias to `mix.exs`.
- Add fast stable alias (`test.fast`) and preserve full stable test path.
- Document speed budgets used for the loop in story criteria and docs.
#### Acceptance Criteria
- `mix precommit` exists and succeeds on a clean tree.
- `mix test.fast` exists and runs only fast stable smoke coverage.
- Full stable suite remains available via `mix test` (`--exclude flaky`).
#### Stable Test Gate
- `mix precommit`
- `mix test.fast`
#### Docs Gate
- Any changed docs mention dual-gate behavior and expected runtime budgets.
#### Example Gate
- Examples include one command set for fast per-story gate and one for full checkpoint gate.
#### Dependencies
- ST-OPS-001

### ST-EXM-001 Weather-Focused Example Consolidation
#### Goal
Consolidate and normalize examples so each major feature family can point to coherent weather-centric demonstrations.
#### Scope
- Normalize strategy markdown under `lib/examples/strategies`.
- Ensure weather strategy suite includes every reasoning strategy example module.
- Refresh `lib/examples/README.md` to map features to runnable examples.
- Review scripts index and mark canonical/demo vs utility scripts.
#### Acceptance Criteria
- Strategy markdown files for CoD/AoT/CoT/ReAct/ToT/GoT/TRM/Adaptive are in `lib/examples/strategies`.
- Weather example index includes CoD in parity with other strategies.
- Docs extras and README links reference normalized strategy example paths.
#### Stable Test Gate
- `mix precommit`
- `mix test.fast`
- `mix test test/jido_ai/examples/weather_strategy_suite_test.exs`
#### Docs Gate
- `mix docs` includes normalized examples without broken path references.
#### Example Gate
- `lib/examples/README.md` provides a single weather matrix mapping all strategy demos.
#### Dependencies
- ST-OPS-001
- ST-OPS-002
