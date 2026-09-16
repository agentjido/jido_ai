# Jido AI V3 learning path

Start with one Agent. Add tools only after the first answer works. The written
guides explain the contracts; the Livebooks let you inspect the same contracts
in a running Agent. All teaching Agents use `Jido.AI.Agent` and its DSL.

Each Livebook starts in MockLLM mode and needs no API key. Change one `backend`
value to `:live` to use the model declared by that notebook's Agent. Mock mode
has a scripted answer and exact checks. Live output can differ.

## Start here

1. [Your first AI Agent](01_first_agent.md) · [Run it](../livebooks/first_answer.livemd)
2. [Add a tool and ReAct](02_tools_and_react.md) · [Run three rounds](../livebooks/three_tool_rounds.livemd)
3. [Where the answer goes](03_results_and_state.md)

## Author the Agent

4. [How the AI DSL fits together](04_dsl_map.md)
5. [Models, profiles, and instructions](05_models_profiles_instructions.md)
6. [Design a tool contract](06_tool_contracts.md)
7. [Structured results and repair](07_structured_results.md) · [Break and repair](../livebooks/repair_result.livemd)
8. [Choose a reasoning method](08_reasoning_methods.md) · [Compare](../livebooks/reasoning_methods.livemd)

## Understand a turn

9. [Anatomy of an AI turn](09_turn_sequence.md)
10. [Long-running turns](10_long_running_turns.md) · [Bound a turn](../livebooks/long_turn.livemd)
11. [Controls and limits](11_controls_and_limits.md)
12. [Stream, steer, and cancel](12_stream_steer_cancel.md) · [Steer a turn](../livebooks/steer_turn.livemd)
13. [Failures and recovery](13_failures_and_recovery.md)

## Govern and inspect

14. [Tool access and effects](14_tool_policy.md) · [Allow and deny](../livebooks/tool_policy.livemd)
15. [Budgets and quotas](15_budgets_and_quotas.md)
16. [Observability and diagnostics](16_observability.md)

## Work with Context

17. [Session, Thread, and Context](17_session_thread_context.md) · [Two requests](../livebooks/two_requests.livemd)
18. [How Context is built](18_context_projection.md)
19. [Multiple Contexts](19_multiple_contexts.md) · [Switch Context](../livebooks/switch_context.livemd)
20. [Checkpoint and resume](20_checkpoint_resume.md) · [Resume](../livebooks/resume_context.livemd)

## Reference

21. [Test your AI Agent](21_testing_agents.md)
22. [DSL reference](22_dsl_reference.md)

The detailed [design documents](../../docs/design/README.md) track design
targets and alignment gaps. These guides describe the public V3 code that a
developer can use now. A proposed feature does not belong in a runnable guide
until it works.
