# Examples Index

All runnable examples now live under `lib/examples`.

## Agents

- `lib/examples/agents/weather_agent.ex` - ReAct weather assistant.
- `lib/examples/agents/browser_agent.ex` - Web browsing/search assistant.
- `lib/examples/agents/task_list_agent.ex` - Task decomposition + execution loop.
- `lib/examples/agents/issue_triage_agent.ex` - GitHub issue triage workflow.
- `lib/examples/agents/api_smoke_test_agent.ex` - HTTP endpoint smoke testing.
- `lib/examples/agents/release_notes_agent.ex` - Graph-of-Thoughts release note synthesis.
- `lib/examples/agents/react_demo_agent.ex` - Minimal ReAct agent.

## Strategy-Specific Weather Agents

- `lib/examples/weather/react_agent.ex`
- `lib/examples/weather/cot_agent.ex`
- `lib/examples/weather/tot_agent.ex`
- `lib/examples/weather/got_agent.ex`
- `lib/examples/weather/trm_agent.ex`
- `lib/examples/weather/adaptive_agent.ex`
- `lib/examples/weather/overview.ex`

## Skills And Tools

- `lib/examples/skills/` - Example skill modules.
- `lib/examples/tools/` - Example action/tool modules.
- `lib/examples/calculator_agent.ex`
- `lib/examples/skills_demo_agent.ex`

## Scripts

Run with `mix run lib/examples/scripts/<name>.exs`.

- `browser_adapter_test.exs`
- `browser_demo.exs`
- `multi_turn_demo.exs`
- `skill_demo.exs`
- `skills_demo.exs`
- `task_list_demo.exs`
- `test_weather_agent.exs`

## Strategy Markdown Snippets

- `lib/examples/strategies/adaptive_strategy.md`
- `lib/examples/strategies/chain_of_thought.md`
- `lib/examples/strategies/react_agent.md`
- `lib/examples/strategies/tree_of_thoughts.md`
