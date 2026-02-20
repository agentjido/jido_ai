# Reasoning Strategy Stories

### ST-STR-001 ReAct Strategy End-To-End
#### Goal
Complete docs/tests/examples for ReAct strategy as the production-default tool-using path.
#### Scope
- Strategy module behavior and runtime adapter coverage.
- Agent macro integration and weather example parity.
- CLI adapter alignment.
#### Acceptance Criteria
- ReAct docs include tool loop flow and request lifecycle contracts.
- Tests cover behavior, error path, and integration with runtime runner.
- Weather example is current and linked from docs index.
#### Stable Test Gate
- `mix precommit`
- `mix test.fast`
- `mix test test/jido_ai/strategy/react_test.exs test/jido_ai/react_agent_test.exs test/jido_ai/react`
#### Docs Gate
- `mix doctor --summary`
#### Example Gate
- `mix run lib/examples/scripts/test_weather_agent.exs` (or documented skip path).
#### Dependencies
- ST-OPS-001
- ST-OPS-002
- ST-EXM-001

### ST-STR-002 Chain-Of-Draft Strategy End-To-End
#### Goal
Complete docs/tests/examples for Chain-of-Draft and add weather parity example module.
#### Scope
- CoD strategy docs and tests.
- Add `Jido.AI.Examples.Weather.CoDAgent` and wire it into weather overview/tests.
- CLI adapter and strategy markdown alignment.
#### Acceptance Criteria
- CoD weather example exists and appears in overview map.
- CoD docs and tests cover happy path, error path, and adapter wiring.
- Strategy markdown lives under normalized `lib/examples/strategies` path.
#### Stable Test Gate
- `mix precommit`
- `mix test.fast`
- `mix test test/jido_ai/strategy/chain_of_draft_test.exs test/jido_ai/cli/adapters/cod_test.exs`
#### Docs Gate
- `mix doctor --summary`
#### Example Gate
- Weather matrix includes CoD command and module reference.
#### Dependencies
- ST-OPS-001
- ST-OPS-002
- ST-EXM-001

### ST-STR-003 Chain-Of-Thought Strategy End-To-End
#### Goal
Complete docs/tests/examples for Chain-of-Thought strategy.
#### Scope
- CoT strategy module contracts and macro docs.
- CLI adapter and weather example parity.
#### Acceptance Criteria
- CoT docs and tests align with request lifecycle behavior.
- Weather CoT example remains canonical and linked in strategy matrix.
- CLI adapter tests cover default/custom options.
#### Stable Test Gate
- `mix precommit`
- `mix test.fast`
- `mix test test/jido_ai/strategy/chain_of_thought_test.exs test/jido_ai/cot_agent_test.exs test/jido_ai/cli/adapters/cot_test.exs`
#### Docs Gate
- `mix doctor --summary`
#### Example Gate
- Weather strategy guide references CoT weather module and command.
#### Dependencies
- ST-OPS-001
- ST-OPS-002
- ST-EXM-001

### ST-STR-004 Algorithm-Of-Thoughts Strategy End-To-End
#### Goal
Complete docs/tests/examples for Algorithm-of-Thoughts strategy.
#### Scope
- AoT strategy and macro docs/tests.
- CLI adapter alignment and weather example parity.
#### Acceptance Criteria
- AoT tests cover options, defaults, and request lifecycle behavior.
- AoT example path is normalized and linked consistently.
- Weather example module is validated in suite tests.
#### Stable Test Gate
- `mix precommit`
- `mix test.fast`
- `mix test test/jido_ai/strategy/algorithm_of_thoughts_test.exs test/jido_ai/aot_agent_test.exs test/jido_ai/cli/adapters/aot_test.exs`
#### Docs Gate
- `mix doctor --summary`
#### Example Gate
- Strategy matrix includes AoT weather run command.
#### Dependencies
- ST-OPS-001
- ST-OPS-002
- ST-EXM-001

### ST-STR-005 Tree-Of-Thoughts Strategy End-To-End
#### Goal
Complete docs/tests/examples for Tree-of-Thoughts strategy and structured result contract.
#### Scope
- ToT strategy module, macro helpers, and result contract docs/tests.
- CLI adapter and weather parity example maintenance.
#### Acceptance Criteria
- ToT docs include structured result fields and control knobs.
- Tests cover helper extraction and configuration defaults.
- Weather ToT example usage remains current and linked.
#### Stable Test Gate
- `mix precommit`
- `mix test.fast`
- `mix test test/jido_ai/strategy/tree_of_thoughts_test.exs test/jido_ai/tot_agent_test.exs test/jido_ai/cli/adapters/tot_test.exs test/jido_ai/tree_of_thoughts`
#### Docs Gate
- `mix doctor --summary`
#### Example Gate
- Strategy matrix includes ToT weather run command.
#### Dependencies
- ST-OPS-001
- ST-OPS-002
- ST-EXM-001

### ST-STR-006 Graph-Of-Thoughts Strategy End-To-End
#### Goal
Complete docs/tests/examples for Graph-of-Thoughts strategy including missing markdown wiring.
#### Scope
- GoT strategy docs/tests and agent macro coverage.
- Add normalized strategy markdown and docs extras wiring.
- Validate weather GoT example parity.
#### Acceptance Criteria
- GoT strategy markdown exists in normalized strategy docs location.
- GoT docs extras include the new markdown path.
- Tests cover strategy behavior and macro lifecycle/error hooks.
#### Stable Test Gate
- `mix precommit`
- `mix test.fast`
- `mix test test/jido_ai/strategy/graph_of_thoughts_test.exs test/jido_ai/got_agent_test.exs test/jido_ai/cli/adapters/got_test.exs test/jido_ai/graph_of_thoughts`
#### Docs Gate
- `mix doctor --summary`
#### Example Gate
- Strategy matrix includes GoT weather run command.
#### Dependencies
- ST-OPS-001
- ST-OPS-002
- ST-EXM-001

### ST-STR-007 TRM Strategy End-To-End
#### Goal
Complete docs/tests/examples for TRM strategy including missing markdown wiring.
#### Scope
- TRM strategy docs/tests for reasoning/act/supervision loop.
- Add normalized TRM strategy markdown and docs extras wiring.
- Validate weather TRM example parity.
#### Acceptance Criteria
- TRM strategy markdown exists in normalized strategy docs location.
- TRM docs explain recursion loop and stopping controls.
- Tests cover TRM machine/reasoning/act/supervision contracts.
#### Stable Test Gate
- `mix precommit`
- `mix test.fast`
- `mix test test/jido_ai/strategy/trm_test.exs test/jido_ai/trm_agent_test.exs test/jido_ai/cli/adapters/trm_test.exs test/jido_ai/trm`
#### Docs Gate
- `mix doctor --summary`
#### Example Gate
- Strategy matrix includes TRM weather run command.
#### Dependencies
- ST-OPS-001
- ST-OPS-002
- ST-EXM-001

### ST-STR-008 Adaptive Strategy End-To-End
#### Goal
Complete docs/tests/examples for Adaptive strategy selection behavior.
#### Scope
- Adaptive strategy docs/tests and macro defaults.
- CLI adapter alignment and weather parity example.
#### Acceptance Criteria
- Adaptive docs include strategy-selection constraints and defaults.
- Tests cover request lifecycle and strategy option mapping.
- Weather adaptive example is linked in strategy matrix and docs.
#### Stable Test Gate
- `mix precommit`
- `mix test.fast`
- `mix test test/jido_ai/strategy/adaptive_test.exs test/jido_ai/adaptive_agent_test.exs test/jido_ai/cli/adapters/adaptive_test.exs`
#### Docs Gate
- `mix doctor --summary`
#### Example Gate
- Strategy matrix includes Adaptive weather run command.
#### Dependencies
- ST-OPS-001
- ST-OPS-002
- ST-EXM-001
