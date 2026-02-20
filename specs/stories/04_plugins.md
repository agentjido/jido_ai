# Plugin Stories

### ST-PLG-001 Chat Plugin End-To-End
#### Goal
Complete docs/tests/examples for `Jido.AI.Plugins.Chat` capability surface.
#### Scope
- `plugin_spec/1`, `mount/2`, schema/state defaults, routes, and transforms.
- Cross-check action routing to chat/tool-calling/LLM actions.
#### Acceptance Criteria
- Plugin docs clearly define chat signal contracts and defaults.
- Tests cover spec/mount/routes/handle_signal/transform_result.
- Example mapping includes chat plugin usage pattern.
#### Stable Test Gate
- `mix precommit`
- `mix test.fast`
- `mix test test/jido_ai/skills/llm/llm_skill_test.exs test/jido_ai/skills/lifecycle_integration_test.exs`
#### Docs Gate
- `mix doctor --summary`
#### Example Gate
- At least one example references plugin-based chat usage.
#### Dependencies
- ST-OPS-001
- ST-OPS-002
- ST-EXM-001
- ST-STR-001

### ST-PLG-002 Planning Plugin End-To-End
#### Goal
Complete docs/tests/examples for `Jido.AI.Plugins.Planning`.
#### Scope
- Validate planning plugin mount defaults, actions, and routes.
- Ensure docs align with planning action behavior.
#### Acceptance Criteria
- Plugin docs include route and defaults contract.
- Tests cover spec/mount/actions and lifecycle integration.
- Example index maps planning plugin to demo usage.
#### Stable Test Gate
- `mix precommit`
- `mix test.fast`
- `mix test test/jido_ai/skills/planning/planning_skill_test.exs test/jido_ai/skills/lifecycle_integration_test.exs`
#### Docs Gate
- `mix doctor --summary`
#### Example Gate
- Add or refresh one planning plugin example snippet.
#### Dependencies
- ST-OPS-001
- ST-OPS-002
- ST-EXM-001

### ST-PLG-003 Reasoning Chain-Of-Draft Plugin End-To-End
#### Goal
Complete docs/tests/examples for `Jido.AI.Plugins.Reasoning.ChainOfDraft`.
#### Scope
- Cover plugin fixed strategy injection behavior and routing.
- Ensure docs explain plugin-to-RunStrategy handoff.
#### Acceptance Criteria
- Tests validate `strategy: :cod` override behavior and signal route.
- Docs include reasoning plugin usage for CoD.
- Example matrix includes plugin execution path.
#### Stable Test Gate
- `mix precommit`
- `mix test.fast`
- `mix test test/jido_ai/plugins/reasoning/chain_of_draft_test.exs test/jido_ai/skills/lifecycle_integration_test.exs`
#### Docs Gate
- `mix doctor --summary`
#### Example Gate
- Include one CoD plugin invocation snippet in docs.
#### Dependencies
- ST-OPS-001
- ST-OPS-002
- ST-EXM-001
- ST-STR-002

### ST-PLG-004 Reasoning Chain-Of-Thought Plugin End-To-End
#### Goal
Complete docs/tests/examples for `Jido.AI.Plugins.Reasoning.ChainOfThought`.
#### Scope
- Cover fixed strategy injection, routes, defaults, and schema behavior.
#### Acceptance Criteria
- Tests validate `strategy: :cot` injection and route contract.
- Docs include CoT plugin usage and defaults.
- Example matrix includes CoT plugin path.
#### Stable Test Gate
- `mix precommit`
- `mix test.fast`
- `mix test test/jido_ai/skills/tool_calling/tool_calling_skill_test.exs test/jido_ai/skills/lifecycle_integration_test.exs`
#### Docs Gate
- `mix doctor --summary`
#### Example Gate
- Add/update CoT plugin snippet.
#### Dependencies
- ST-OPS-001
- ST-OPS-002
- ST-EXM-001
- ST-STR-003

### ST-PLG-005 Reasoning Algorithm-Of-Thoughts Plugin End-To-End
#### Goal
Complete docs/tests/examples for `Jido.AI.Plugins.Reasoning.AlgorithmOfThoughts`.
#### Scope
- Cover fixed strategy injection and strategy-specific options handling.
#### Acceptance Criteria
- Tests validate `strategy: :aot` injection and route contract.
- Docs include AoT plugin usage guidance.
- Example matrix includes AoT plugin path.
#### Stable Test Gate
- `mix precommit`
- `mix test.fast`
- `mix test test/jido_ai/skills/lifecycle_integration_test.exs test/jido_ai/skills/schema_integration_test.exs`
#### Docs Gate
- `mix doctor --summary`
#### Example Gate
- Add/update AoT plugin snippet.
#### Dependencies
- ST-OPS-001
- ST-OPS-002
- ST-EXM-001
- ST-STR-004

### ST-PLG-006 Reasoning Tree-Of-Thoughts Plugin End-To-End
#### Goal
Complete docs/tests/examples for `Jido.AI.Plugins.Reasoning.TreeOfThoughts`.
#### Scope
- Cover ToT plugin strategy injection and route contracts.
#### Acceptance Criteria
- Tests validate `strategy: :tot` injection and route contract.
- Docs include ToT plugin usage and options.
- Example matrix includes ToT plugin path.
#### Stable Test Gate
- `mix precommit`
- `mix test.fast`
- `mix test test/jido_ai/skills/reasoning/reasoning_skill_test.exs test/jido_ai/skills/lifecycle_integration_test.exs`
#### Docs Gate
- `mix doctor --summary`
#### Example Gate
- Add/update ToT plugin snippet.
#### Dependencies
- ST-OPS-001
- ST-OPS-002
- ST-EXM-001
- ST-STR-005

### ST-PLG-007 Reasoning Graph-Of-Thoughts Plugin End-To-End
#### Goal
Complete docs/tests/examples for `Jido.AI.Plugins.Reasoning.GraphOfThoughts`.
#### Scope
- Cover GoT plugin strategy injection and route contracts.
#### Acceptance Criteria
- Tests validate `strategy: :got` injection and route contract.
- Docs include GoT plugin usage and options.
- Example matrix includes GoT plugin path.
#### Stable Test Gate
- `mix precommit`
- `mix test.fast`
- `mix test test/jido_ai/skills/lifecycle_integration_test.exs test/jido_ai/skills/schema_integration_test.exs`
#### Docs Gate
- `mix doctor --summary`
#### Example Gate
- Add/update GoT plugin snippet.
#### Dependencies
- ST-OPS-001
- ST-OPS-002
- ST-EXM-001
- ST-STR-006

### ST-PLG-008 Reasoning TRM Plugin End-To-End
#### Goal
Complete docs/tests/examples for `Jido.AI.Plugins.Reasoning.TRM`.
#### Scope
- Cover TRM plugin strategy injection and route contracts.
#### Acceptance Criteria
- Tests validate `strategy: :trm` injection and route contract.
- Docs include TRM plugin usage and options.
- Example matrix includes TRM plugin path.
#### Stable Test Gate
- `mix precommit`
- `mix test.fast`
- `mix test test/jido_ai/skills/lifecycle_integration_test.exs test/jido_ai/skills/schema_integration_test.exs`
#### Docs Gate
- `mix doctor --summary`
#### Example Gate
- Add/update TRM plugin snippet.
#### Dependencies
- ST-OPS-001
- ST-OPS-002
- ST-EXM-001
- ST-STR-007

### ST-PLG-009 Reasoning Adaptive Plugin End-To-End
#### Goal
Complete docs/tests/examples for `Jido.AI.Plugins.Reasoning.Adaptive`.
#### Scope
- Cover adaptive plugin strategy injection and route contracts.
#### Acceptance Criteria
- Tests validate `strategy: :adaptive` injection and route contract.
- Docs include adaptive plugin usage and defaults.
- Example matrix includes adaptive plugin path.
#### Stable Test Gate
- `mix precommit`
- `mix test.fast`
- `mix test test/jido_ai/skills/lifecycle_integration_test.exs test/jido_ai/skills/schema_integration_test.exs`
#### Docs Gate
- `mix doctor --summary`
#### Example Gate
- Add/update adaptive plugin snippet.
#### Dependencies
- ST-OPS-001
- ST-OPS-002
- ST-EXM-001
- ST-STR-008

### ST-PLG-010 ModelRouting Plugin End-To-End
#### Goal
Complete docs/tests/examples for `Jido.AI.Plugins.ModelRouting`.
#### Scope
- Cover route matching behavior, explicit override behavior, wildcard contracts.
#### Acceptance Criteria
- Docs include route precedence and wildcard behavior.
- Tests cover default route application and explicit model bypass.
- Example snippets show config shape used in production.
#### Stable Test Gate
- `mix precommit`
- `mix test.fast`
- `mix test test/jido_ai/plugins/model_routing_test.exs`
#### Docs Gate
- `mix doctor --summary`
#### Example Gate
- Include one `model_routing` plugin config example.
#### Dependencies
- ST-OPS-001
- ST-OPS-002
- ST-EXM-001

### ST-PLG-011 Policy Plugin End-To-End
#### Goal
Complete docs/tests/examples for `Jido.AI.Plugins.Policy`.
#### Scope
- Cover policy rewrite behavior, normalization, and sanitization contracts.
#### Acceptance Criteria
- Docs define enforce mode behavior and rewrite semantics.
- Tests cover policy_violation rewrite and envelope normalization.
- Example includes policy hardening config block.
#### Stable Test Gate
- `mix precommit`
- `mix test.fast`
- `mix test test/jido_ai/plugins/policy_test.exs`
#### Docs Gate
- `mix doctor --summary`
#### Example Gate
- Include one policy plugin config example.
#### Dependencies
- ST-OPS-001
- ST-OPS-002
- ST-EXM-001

### ST-PLG-012 Retrieval Plugin End-To-End
#### Goal
Complete docs/tests/examples for `Jido.AI.Plugins.Retrieval`.
#### Scope
- Cover prompt enrichment behavior, disable flags, and namespace config.
#### Acceptance Criteria
- Docs define retrieval enrichment lifecycle and opt-out behavior.
- Tests cover enrichment path and skip path.
- Example includes retrieval plugin mount snippet.
#### Stable Test Gate
- `mix precommit`
- `mix test.fast`
- `mix test test/jido_ai/plugins/retrieval_test.exs`
#### Docs Gate
- `mix doctor --summary`
#### Example Gate
- Include one retrieval plugin usage example.
#### Dependencies
- ST-OPS-001
- ST-OPS-002
- ST-EXM-001

### ST-PLG-013 Quota Plugin End-To-End
#### Goal
Complete docs/tests/examples for `Jido.AI.Plugins.Quota`.
#### Scope
- Cover quota accounting and request rejection behavior.
#### Acceptance Criteria
- Docs define quota state keys and budget rejection contract.
- Tests cover usage accounting and request rewrite behavior.
- Example includes quota config snippet and expected rejection shape.
#### Stable Test Gate
- `mix precommit`
- `mix test.fast`
- `mix test test/jido_ai/plugins/quota_test.exs`
#### Docs Gate
- `mix doctor --summary`
#### Example Gate
- Include one quota plugin usage example.
#### Dependencies
- ST-OPS-001
- ST-OPS-002
- ST-EXM-001

### ST-PLG-014 TaskSupervisor Plugin End-To-End
#### Goal
Document and harden `Jido.AI.Plugins.TaskSupervisor` as the internal default plugin contract.
#### Scope
- Cover lifecycle behavior, state key usage, and runtime cleanup expectations.
- Ensure docs distinguish internal/runtime plugin from capability plugins.
#### Acceptance Criteria
- Internal plugin contract is documented in developer guide.
- Tests assert plugin presence and runtime lifecycle expectations.
- No public capability docs incorrectly classify TaskSupervisor as end-user feature.
#### Stable Test Gate
- `mix precommit`
- `mix test.fast`
- `mix test test/jido_ai/plugin_stack_test.exs test/jido_ai/skills/lifecycle_integration_test.exs`
#### Docs Gate
- `mix doctor --summary`
#### Example Gate
- Example docs mention TaskSupervisor only as runtime infrastructure.
#### Dependencies
- ST-OPS-001
- ST-OPS-002
- ST-EXM-001
