# Examples Index

All runnable examples now live under `lib/examples`.

## Story Loop Gates

Fast per-story gate command set (target runtime budget: under 90 seconds on a warm cache):

```bash
mix precommit
mix test.fast
```

Full checkpoint gate command set (target runtime budget: under 10 minutes on a warm cache):

```bash
mix test
```

## Weather Strategy Matrix

Canonical weather overview module:
- `lib/examples/weather/overview.ex`

| Strategy | Weather Module | Strategy Markdown | CLI Demo |
| --- | --- | --- | --- |
| ReAct | `Jido.AI.Examples.Weather.ReActAgent` (`lib/examples/weather/react_agent.ex`) | `lib/examples/strategies/react.md` | `mix jido_ai --agent Jido.AI.Examples.Weather.ReActAgent "Do I need an umbrella in Seattle tomorrow morning?"` |
| CoD | `Jido.AI.Examples.Weather.CoDAgent` (`lib/examples/weather/cod_agent.ex`) | `lib/examples/strategies/cod.md` | `mix jido_ai --agent Jido.AI.Examples.Weather.CoDAgent "Give me a fast weather-aware commute recommendation with one backup."` |
| AoT | `Jido.AI.Examples.Weather.AoTAgent` (`lib/examples/weather/aot_agent.ex`) | `lib/examples/strategies/aot.md` | `mix jido_ai --agent Jido.AI.Examples.Weather.AoTAgent "Find the best weather-safe weekend option with one backup."` |
| CoT | `Jido.AI.Examples.Weather.CoTAgent` (`lib/examples/weather/cot_agent.ex`) | `lib/examples/strategies/cot.md` | `mix jido_ai --agent Jido.AI.Examples.Weather.CoTAgent "How should I decide between biking and transit in rainy weather?"` |
| ToT | `Jido.AI.Examples.Weather.ToTAgent` (`lib/examples/weather/tot_agent.ex`) | `lib/examples/strategies/tot.md` | `mix jido_ai --agent Jido.AI.Examples.Weather.ToTAgent "Plan three weekend options for Boston if weather is uncertain."` |
| GoT | `Jido.AI.Examples.Weather.GoTAgent` (`lib/examples/weather/got_agent.ex`) | `lib/examples/strategies/got.md` | `mix jido_ai --agent Jido.AI.Examples.Weather.GoTAgent "Compare weather risks across NYC, Chicago, and Denver for a trip."` |
| TRM | `Jido.AI.Examples.Weather.TRMAgent` (`lib/examples/weather/trm_agent.ex`) | `lib/examples/strategies/trm.md` | `mix jido_ai --agent Jido.AI.Examples.Weather.TRMAgent "Stress test this storm-prep plan and improve it."` |
| Adaptive | `Jido.AI.Examples.Weather.AdaptiveAgent` (`lib/examples/weather/adaptive_agent.ex`) | `lib/examples/strategies/adaptive.md` | `mix jido_ai --agent Jido.AI.Examples.Weather.AdaptiveAgent "I need a weather-aware commute and backup plan for tomorrow."` |

## Feature Family Map

| Feature Family | Runnable Examples |
| --- | --- |
| ReAct baseline agents | `lib/examples/agents/weather_agent.ex`, `lib/examples/agents/react_demo_agent.ex` |
| Weather strategy suite | `lib/examples/weather/*.ex`, `lib/examples/strategies/*.md` |
| Browser + task workflows | `lib/examples/agents/browser_agent.ex`, `lib/examples/agents/task_list_agent.ex`, `lib/examples/agents/issue_triage_agent.ex` |
| API + release workflows | `lib/examples/agents/api_smoke_test_agent.ex`, `lib/examples/agents/release_notes_agent.ex` |
| Skills and tools | `lib/examples/skills/`, `lib/examples/tools/`, `lib/examples/skills_demo_agent.ex`, `lib/examples/calculator_agent.ex` |

## Plugin Capability Pattern

| Capability | Usage Pattern |
| --- | --- |
| Chat plugin | Mount `Jido.AI.Plugins.Chat` and send `chat.message` signals for tool-aware chat routing. |
| Planning plugin | Mount `Jido.AI.Plugins.Planning` and send planning signals for plan/decompose/prioritize actions. |
| Reasoning CoD plugin | Mount `Jido.AI.Plugins.Reasoning.ChainOfDraft` and send `reasoning.cod.run` for fixed `:cod` strategy execution. |
| Reasoning CoT plugin | Mount `Jido.AI.Plugins.Reasoning.ChainOfThought` and send `reasoning.cot.run` for fixed `:cot` strategy execution. |
| Reasoning AoT plugin | Mount `Jido.AI.Plugins.Reasoning.AlgorithmOfThoughts` and send `reasoning.aot.run` for fixed `:aot` strategy execution. |

```elixir
defmodule MyApp.ChatAgent do
  use Jido.AI.Agent,
    name: "chat_agent",
    plugins: [
      {Jido.AI.Plugins.Chat,
       %{
         default_model: :capable,
         auto_execute: true,
         tools: [MyApp.Actions.WeatherLookup]
       }}
    ]
end

signal = Jido.Signal.new!("chat.message", %{prompt: "Should I bike to work in Seattle tomorrow?"}, source: "/cli")
# Routes to Jido.AI.Actions.ToolCalling.CallWithTools via Jido.AI.Plugins.Chat
```

```elixir
defmodule MyApp.PlanningAgent do
  use Jido.AI.Agent,
    name: "planning_agent",
    plugins: [
      {Jido.AI.Plugins.Planning,
       %{
         default_model: :planning,
         default_max_tokens: 4096,
         default_temperature: 0.7
       }}
    ]
end

signal = Jido.Signal.new!(
  "planning.plan",
  %{
    goal: "Ship v1 of a note-taking app",
    constraints: ["Team of 2 engineers", "8 week timeline"],
    resources: ["Existing auth service", "Hosted Postgres"]
  },
  source: "/cli"
)
# Routes to Jido.AI.Actions.Planning.Plan via Jido.AI.Plugins.Planning
```

```elixir
defmodule MyApp.ReasoningPluginAgent do
  use Jido.AI.Agent,
    name: "reasoning_plugin_agent",
    plugins: [
      {Jido.AI.Plugins.Reasoning.ChainOfDraft,
       %{
         default_model: :reasoning,
         timeout: 30_000,
         options: %{llm_timeout_ms: 20_000}
       }}
    ]
end

signal = Jido.Signal.new!("reasoning.cod.run", %{prompt: "Summarize risks with one fallback plan."}, source: "/cli")
# Routes to Jido.AI.Actions.Reasoning.RunStrategy via Jido.AI.Plugins.Reasoning.ChainOfDraft
```

```elixir
defmodule MyApp.ChainOfThoughtPluginAgent do
  use Jido.AI.Agent,
    name: "reasoning_cot_plugin_agent",
    plugins: [
      {Jido.AI.Plugins.Reasoning.ChainOfThought,
       %{
         default_model: :reasoning,
         timeout: 30_000,
         options: %{llm_timeout_ms: 20_000}
       }}
    ]
end

signal = Jido.Signal.new!("reasoning.cot.run", %{prompt: "Show your reasoning with one backup plan."}, source: "/cli")
# Routes to Jido.AI.Actions.Reasoning.RunStrategy via Jido.AI.Plugins.Reasoning.ChainOfThought
```

```elixir
defmodule MyApp.AlgorithmOfThoughtsPluginAgent do
  use Jido.AI.Agent,
    name: "reasoning_aot_plugin_agent",
    plugins: [
      {Jido.AI.Plugins.Reasoning.AlgorithmOfThoughts,
       %{
         default_model: :reasoning,
         timeout: 30_000,
         options: %{profile: :standard, search_style: :dfs, llm_timeout_ms: 20_000}
       }}
    ]
end

signal =
  Jido.Signal.new!(
    "reasoning.aot.run",
    %{
      prompt: "Solve this in algorithmic steps and include one fallback."
    },
    source: "/cli"
  )

# Routes to Jido.AI.Actions.Reasoning.RunStrategy via Jido.AI.Plugins.Reasoning.AlgorithmOfThoughts
```

## Script Index

Run scripts with `mix run lib/examples/scripts/<name>.exs`.

| Script | Category | Purpose | Prerequisites / Skip Path |
| --- | --- | --- | --- |
| `browser_demo.exs` | Canonical demo | Interactive browser-assisted workflow. | Project root; browser deps available. |
| `multi_turn_demo.exs` | Canonical demo | Multi-turn agent request lifecycle walkthrough. | Project root. |
| `task_list_demo.exs` | Canonical demo | Task decomposition and execution loop. | Project root. |
| `skill_demo.exs` | Canonical demo | Single skill flow walkthrough. | Project root; if `priv/skills/code-review/SKILL.md` is missing, script prints skip guidance and continues. |
| `skills_demo.exs` | Canonical demo | Multi-skill orchestration demo. | Requires `priv/skills/unit-converter/SKILL.md`; if `ANTHROPIC_API_KEY` is not set, agent interaction section is skipped. |
| `browser_adapter_test.exs` | Utility verification | Browser adapter sanity checks. | Project root; browser deps available. |
| `test_weather_agent.exs` | Utility verification | Weather agent smoke check script. | Project root; requires live provider credentials and runtime network access, otherwise use documented skip path in `lib/examples/strategies/react.md`. |
