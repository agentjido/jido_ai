# Story Traceability Matrix

| Story ID | Theme | Story File | Depends On | Exit Signal |
| --- | --- | --- | --- | --- |
| ST-OPS-001 | Ops | specs/stories/01_ops_examples_core.md | None | Backlog files and matrix created |
| ST-OPS-002 | Ops | specs/stories/01_ops_examples_core.md | ST-OPS-001 | `mix precommit` and `mix test.fast` are available |
| ST-EXM-001 | Examples | specs/stories/01_ops_examples_core.md | ST-OPS-001, ST-OPS-002 | Weather-focused example matrix is consolidated |
| ST-SKL-001 | Skills | specs/stories/02_skills_runtime_cli.md | ST-OPS-001, ST-OPS-002 | Skills docs/tests/examples pass with fast gate |
| ST-RTC-001 | Runtime Core | specs/stories/02_skills_runtime_cli.md | ST-OPS-001, ST-OPS-002 | Request/Thread/Turn contracts documented and tested |
| ST-RTC-002 | Observability/Security | specs/stories/02_skills_runtime_cli.md | ST-OPS-001, ST-OPS-002 | Signals/observe/validation hardening complete |
| ST-RTC-003 | CLI Runtime | specs/stories/02_skills_runtime_cli.md | ST-OPS-001, ST-OPS-002 | CLI docs/tests/examples aligned |
| ST-STR-001 | Strategy ReAct | specs/stories/03_strategies.md | ST-OPS-001, ST-OPS-002, ST-EXM-001 | ReAct strategy has docs/tests/weather parity |
| ST-STR-002 | Strategy CoD | specs/stories/03_strategies.md | ST-OPS-001, ST-OPS-002, ST-EXM-001 | CoD strategy has docs/tests/weather parity |
| ST-STR-003 | Strategy CoT | specs/stories/03_strategies.md | ST-OPS-001, ST-OPS-002, ST-EXM-001 | CoT strategy has docs/tests/weather parity |
| ST-STR-004 | Strategy AoT | specs/stories/03_strategies.md | ST-OPS-001, ST-OPS-002, ST-EXM-001 | AoT strategy has docs/tests/weather parity |
| ST-STR-005 | Strategy ToT | specs/stories/03_strategies.md | ST-OPS-001, ST-OPS-002, ST-EXM-001 | ToT strategy has docs/tests/weather parity |
| ST-STR-006 | Strategy GoT | specs/stories/03_strategies.md | ST-OPS-001, ST-OPS-002, ST-EXM-001 | GoT strategy has docs/tests/weather parity |
| ST-STR-007 | Strategy TRM | specs/stories/03_strategies.md | ST-OPS-001, ST-OPS-002, ST-EXM-001 | TRM strategy has docs/tests/weather parity |
| ST-STR-008 | Strategy Adaptive | specs/stories/03_strategies.md | ST-OPS-001, ST-OPS-002, ST-EXM-001 | Adaptive strategy has docs/tests/weather parity |
| ST-PLG-001 | Plugin Chat | specs/stories/04_plugins.md | ST-OPS-001, ST-OPS-002, ST-EXM-001, ST-STR-001 | Chat plugin surface is complete |
| ST-PLG-002 | Plugin Planning | specs/stories/04_plugins.md | ST-OPS-001, ST-OPS-002, ST-EXM-001 | Planning plugin surface is complete |
| ST-PLG-003 | Plugin Reasoning CoD | specs/stories/04_plugins.md | ST-OPS-001, ST-OPS-002, ST-EXM-001, ST-STR-002 | CoD reasoning plugin is complete |
| ST-PLG-004 | Plugin Reasoning CoT | specs/stories/04_plugins.md | ST-OPS-001, ST-OPS-002, ST-EXM-001, ST-STR-003 | CoT reasoning plugin is complete |
| ST-PLG-005 | Plugin Reasoning AoT | specs/stories/04_plugins.md | ST-OPS-001, ST-OPS-002, ST-EXM-001, ST-STR-004 | AoT reasoning plugin is complete |
| ST-PLG-006 | Plugin Reasoning ToT | specs/stories/04_plugins.md | ST-OPS-001, ST-OPS-002, ST-EXM-001, ST-STR-005 | ToT reasoning plugin is complete |
| ST-PLG-007 | Plugin Reasoning GoT | specs/stories/04_plugins.md | ST-OPS-001, ST-OPS-002, ST-EXM-001, ST-STR-006 | GoT reasoning plugin is complete |
| ST-PLG-008 | Plugin Reasoning TRM | specs/stories/04_plugins.md | ST-OPS-001, ST-OPS-002, ST-EXM-001, ST-STR-007 | TRM reasoning plugin is complete |
| ST-PLG-009 | Plugin Reasoning Adaptive | specs/stories/04_plugins.md | ST-OPS-001, ST-OPS-002, ST-EXM-001, ST-STR-008 | Adaptive reasoning plugin is complete |
| ST-PLG-010 | Plugin ModelRouting | specs/stories/04_plugins.md | ST-OPS-001, ST-OPS-002, ST-EXM-001 | Model routing plugin is complete |
| ST-PLG-011 | Plugin Policy | specs/stories/04_plugins.md | ST-OPS-001, ST-OPS-002, ST-EXM-001 | Policy plugin is complete |
| ST-PLG-012 | Plugin Retrieval | specs/stories/04_plugins.md | ST-OPS-001, ST-OPS-002, ST-EXM-001 | Retrieval plugin is complete |
| ST-PLG-013 | Plugin Quota | specs/stories/04_plugins.md | ST-OPS-001, ST-OPS-002, ST-EXM-001 | Quota plugin is complete |
| ST-PLG-014 | Plugin TaskSupervisor | specs/stories/04_plugins.md | ST-OPS-001, ST-OPS-002, ST-EXM-001 | TaskSupervisor plugin contracts are covered |
| ST-ACT-001 | Actions LLM | specs/stories/05_actions.md | ST-OPS-001, ST-OPS-002, ST-EXM-001 | LLM action set is complete |
| ST-ACT-002 | Actions Tool Calling | specs/stories/05_actions.md | ST-OPS-001, ST-OPS-002, ST-EXM-001 | Tool-calling action set is complete |
| ST-ACT-003 | Actions Planning | specs/stories/05_actions.md | ST-OPS-001, ST-OPS-002, ST-EXM-001 | Planning action set is complete |
| ST-ACT-004 | Actions Reasoning | specs/stories/05_actions.md | ST-OPS-001, ST-OPS-002, ST-EXM-001 | Reasoning action set is complete |
| ST-ACT-005 | Actions Retrieval | specs/stories/05_actions.md | ST-OPS-001, ST-OPS-002, ST-EXM-001 | Retrieval action set has direct tests/docs/examples |
| ST-ACT-006 | Actions Quota | specs/stories/05_actions.md | ST-OPS-001, ST-OPS-002, ST-EXM-001 | Quota action set has direct tests/docs/examples |
| ST-QAL-001 | Final Quality | specs/stories/06_quality.md | ST-OPS-001, ST-OPS-002, ST-EXM-001, ST-SKL-001, ST-RTC-001, ST-RTC-002, ST-RTC-003, ST-STR-001, ST-STR-002, ST-STR-003, ST-STR-004, ST-STR-005, ST-STR-006, ST-STR-007, ST-STR-008, ST-PLG-001, ST-PLG-002, ST-PLG-003, ST-PLG-004, ST-PLG-005, ST-PLG-006, ST-PLG-007, ST-PLG-008, ST-PLG-009, ST-PLG-010, ST-PLG-011, ST-PLG-012, ST-PLG-013, ST-PLG-014, ST-ACT-001, ST-ACT-002, ST-ACT-003, ST-ACT-004, ST-ACT-005, ST-ACT-006 | Full stable quality gate passes |
