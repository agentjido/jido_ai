# Final Quality Story

### ST-QAL-001 Full Stable Quality Checkpoint
#### Goal
Run the final quality checkpoint after all feature stories are complete and verify traceability closure.
#### Scope
- Run full stable suite, doc checks, and coverage checks.
- Verify all traceability rows correspond to completed story commits.
- Capture final timing metrics for fast and full gates.
#### Acceptance Criteria
- `mix test --exclude flaky` passes.
- `mix doctor --summary` passes.
- `mix coveralls` passes configured threshold.
- Every story row in `00_traceability_matrix.md` is represented by a `feat(story): ST-...` commit.
#### Stable Test Gate
- `mix test --exclude flaky`
#### Docs Gate
- `mix doctor --summary`
- `mix docs`
#### Example Gate
- Spot-check one representative example per feature family (skills, strategies, plugins, actions).
#### Dependencies
- ST-OPS-001
- ST-OPS-002
- ST-EXM-001
- ST-SKL-001
- ST-RTC-001
- ST-RTC-002
- ST-RTC-003
- ST-STR-001
- ST-STR-002
- ST-STR-003
- ST-STR-004
- ST-STR-005
- ST-STR-006
- ST-STR-007
- ST-STR-008
- ST-PLG-001
- ST-PLG-002
- ST-PLG-003
- ST-PLG-004
- ST-PLG-005
- ST-PLG-006
- ST-PLG-007
- ST-PLG-008
- ST-PLG-009
- ST-PLG-010
- ST-PLG-011
- ST-PLG-012
- ST-PLG-013
- ST-PLG-014
- ST-ACT-001
- ST-ACT-002
- ST-ACT-003
- ST-ACT-004
- ST-ACT-005
- ST-ACT-006
