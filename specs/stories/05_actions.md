# Action Set Stories

### ST-ACT-001 LLM Actions Set End-To-End
#### Goal
Complete docs/tests/examples for `Chat`, `Complete`, `Embed`, and `GenerateObject` actions.
#### Scope
- Ensure schema, defaults, model resolution, and error handling are covered.
- Ensure action catalog and examples map each LLM action to use cases.
#### Acceptance Criteria
- Tests cover happy path, validation failures, and explicit override behavior.
- Docs identify when to use each LLM action.
- Examples include at least one runnable pattern per action class.
#### Stable Test Gate
- `mix precommit`
- `mix test.fast`
- `mix test test/jido_ai/skills/llm/actions`
#### Docs Gate
- `mix doctor --summary`
#### Example Gate
- Action catalog entries reference concrete example snippets.
#### Dependencies
- ST-OPS-001
- ST-OPS-002
- ST-EXM-001

### ST-ACT-002 Tool-Calling Actions Set End-To-End
#### Goal
Complete docs/tests/examples for `CallWithTools`, `ExecuteTool`, and `ListTools` actions.
#### Scope
- Cover schemas, defaults, auto-execute loop behavior, and deterministic terminal shapes.
- Ensure docs explain security filtering and tool registry behavior.
#### Acceptance Criteria
- Tests cover happy path, validation errors, and fallback context paths.
- Docs define tool map/context/plugin-state precedence.
- Examples show both one-shot and auto-execute workflows.
#### Stable Test Gate
- `mix precommit`
- `mix test.fast`
- `mix test test/jido_ai/skills/tool_calling/actions`
#### Docs Gate
- `mix doctor --summary`
#### Example Gate
- Include at least one tool-calling walkthrough in guides/examples.
#### Dependencies
- ST-OPS-001
- ST-OPS-002
- ST-EXM-001

### ST-ACT-003 Planning Actions Set End-To-End
#### Goal
Complete docs/tests/examples for `Plan`, `Decompose`, and `Prioritize` actions.
#### Scope
- Cover schema constraints/defaults and model/plugin-state override behavior.
- Ensure planning docs and plugin docs are consistent.
#### Acceptance Criteria
- Tests cover happy path and validation failures across all planning actions.
- Docs include clear selection guidance between plan/decompose/prioritize.
- Examples include one planning workflow with task decomposition.
#### Stable Test Gate
- `mix precommit`
- `mix test.fast`
- `mix test test/jido_ai/skills/planning/actions`
#### Docs Gate
- `mix doctor --summary`
#### Example Gate
- Include at least one planning example snippet.
#### Dependencies
- ST-OPS-001
- ST-OPS-002
- ST-EXM-001

### ST-ACT-004 Reasoning Actions Set End-To-End
#### Goal
Complete docs/tests/examples for `Analyze`, `Infer`, `Explain`, and `RunStrategy` with stable-speed split guidance.
#### Scope
- Cover schema/error behavior for reasoning template actions.
- Split long `RunStrategy` coverage into fast-smoke vs full-stable coverage strategy.
#### Acceptance Criteria
- Tests cover happy path and validation/security paths for analyze/infer/explain.
- `RunStrategy` tests have explicit fast gate subset and full checkpoint subset.
- Docs clarify output contracts and strategy parameter requirements.
#### Stable Test Gate
- `mix precommit`
- `mix test.fast`
- `mix test test/jido_ai/skills/reasoning/actions/analyze_action_test.exs test/jido_ai/skills/reasoning/actions/infer_action_test.exs test/jido_ai/skills/reasoning/actions/explain_action_test.exs`
#### Docs Gate
- `mix doctor --summary`
#### Example Gate
- Include one reasoning-action invocation example and one strategy-run example.
#### Dependencies
- ST-OPS-001
- ST-OPS-002
- ST-EXM-001

### ST-ACT-005 Retrieval Actions Set End-To-End
#### Goal
Add direct docs/tests/examples for retrieval actions `UpsertMemory`, `RecallMemory`, and `ClearMemory`.
#### Scope
- Add direct action-level tests (not only plugin-level coverage).
- Update action catalog and retrieval docs to include these actions explicitly.
#### Acceptance Criteria
- Retrieval action modules have direct tests for happy and failure paths.
- Docs mention retrieval action contracts and parameters.
- Examples include one retrieval action usage snippet.
#### Stable Test Gate
- `mix precommit`
- `mix test.fast`
- `mix test test/jido_ai/actions/retrieval`
#### Docs Gate
- `mix doctor --summary`
#### Example Gate
- Include one retrieval action example in docs/examples.
#### Dependencies
- ST-OPS-001
- ST-OPS-002
- ST-EXM-001

### ST-ACT-006 Quota Actions Set End-To-End
#### Goal
Add direct docs/tests/examples for quota actions `GetStatus` and `Reset`.
#### Scope
- Add direct action-level tests for quota action behavior.
- Update docs to clarify action contracts and plugin interplay.
#### Acceptance Criteria
- Quota action modules have direct tests for happy and edge/error paths.
- Docs include quota action usage and expected return shapes.
- Examples include one quota action invocation snippet.
#### Stable Test Gate
- `mix precommit`
- `mix test.fast`
- `mix test test/jido_ai/actions/quota`
#### Docs Gate
- `mix doctor --summary`
#### Example Gate
- Include one quota action example in docs/examples.
#### Dependencies
- ST-OPS-001
- ST-OPS-002
- ST-EXM-001
