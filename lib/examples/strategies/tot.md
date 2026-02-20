# ToT Weather Example

Canonical weather module: `lib/examples/weather/tot_agent.ex`.

Related index docs:
- `README.md`
- `lib/examples/README.md`
- `lib/examples/weather/overview.ex`

## ToT Search Flow

1. Caller submits with `explore/3` or `explore_sync/3` (`ai.tot.query`).
2. `Jido.AI.Reasoning.TreeOfThoughts.Strategy` maps the request into machine messages (`:tot_start`, `:tot_llm_result`, `:tot_llm_partial`).
3. Strategy emits `Jido.AI.Directive.LLMStream` for generation/evaluation turns and applies `ai.llm.delta` and `ai.llm.response` updates.
4. When tool calls are present, strategy executes `Jido.AI.Directive.ToolExec` rounds and feeds tool results back into the same request-id conversation.
5. Completion returns a structured ToT result payload through request tracking (`await/2`) and snapshot state.

## Structured Result Contract

`Jido.AI.ToTAgent` returns a structured map (not a plain string):

- `best`: highest-ranked candidate map (`content`, `score`, `path_ids`, `path_text`)
- `candidates`: ranked top-K leaf candidates
- `termination`: `%{reason, status, depth_reached, node_count, duration_ms}`
- `tree`: `%{node_count, frontier_size, traversal_strategy, max_depth, branching_factor}`
- `usage`: accumulated provider usage metadata
- `diagnostics`: parser mode/retries, convergence, and tool-round diagnostics

Helper extraction APIs exposed by `Jido.AI.ToTAgent`:

- `best_answer/1`
- `top_candidates/2`
- `result_summary/1`

## ToT Control Knobs

Core exploration controls:
- `branching_factor`, `max_depth`, `traversal_strategy`
- `top_k`, `min_depth`, `max_nodes`, `max_duration_ms`, `beam_width`
- `early_success_threshold`, `convergence_window`, `min_score_improvement`
- `max_parse_retries`

Tool orchestration controls:
- `tools`, `tool_context`
- `tool_timeout_ms`, `tool_max_retries`, `tool_retry_backoff_ms`
- `max_tool_round_trips`

## CLI Adapter Alignment

`Jido.AI.Examples.Weather.ToTAgent.cli_adapter/0` returns `Jido.AI.Reasoning.TreeOfThoughts.CLIAdapter`, the canonical `mix jido_ai` adapter for ToT weather runs.

```bash
mix jido_ai --agent Jido.AI.Examples.Weather.ToTAgent "Plan three weekend options for Boston if weather is uncertain."
```

```elixir
{:ok, pid} = Jido.AgentServer.start_link(agent: Jido.AI.Examples.Weather.ToTAgent)

{:ok, result} =
  Jido.AI.Examples.Weather.ToTAgent.weekend_options_sync(
    pid,
    "Boston, MA"
  )

IO.puts("Best: #{Jido.AI.Examples.Weather.ToTAgent.best_answer(result)}")
IO.puts(Jido.AI.Examples.Weather.ToTAgent.format_top_options(result, 3))
```
