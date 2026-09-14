# 09_03: Algorithm of Thoughts

This example declares `:algorithm_of_thoughts` in the canonical AI DSL. AoT
uses one model generation with algorithmic search guidance, then parses the
response into its result map.

```elixir
reasoning :algorithm_of_thoughts do
  model(:answer)
  options(profile: :short, search_style: :dfs, require_explicit_answer: true)
end
```

AoT does not execute tools or accept steering. The examples cover method
options, typed answers, repair, request lifecycle, controls, telemetry,
Signals, errors, cancellation, and committed result inspection.

```sh
mix test test/examples/09_reasoning/09_03_aot --include example --seed 0
```
