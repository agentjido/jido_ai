# Reasoning Action Snippets

Run these from the repository root with provider credentials configured.

## Analyze Action

```bash
mix run -e 'alias Jido.AI.Actions.Reasoning.Analyze; {:ok, result} = Jido.Exec.run(Analyze, %{input: "Customer churn increased 18% this quarter while support volume stayed flat.", analysis_type: :summary}); IO.inspect(result, label: "analyze")'
```

## Infer Action

```bash
mix run -e 'alias Jido.AI.Actions.Reasoning.Infer; {:ok, result} = Jido.Exec.run(Infer, %{premises: "All production incidents trigger a postmortem. Incident INC-42 was a production incident.", question: "Should INC-42 have a postmortem?"}); IO.inspect(result, label: "infer")'
```

## Explain Action

```bash
mix run -e 'alias Jido.AI.Actions.Reasoning.Explain; {:ok, result} = Jido.Exec.run(Explain, %{topic: "GenServer supervision trees", detail_level: :intermediate, audience: "backend engineers", include_examples: true}); IO.inspect(result, label: "explain")'
```

## RunStrategy Action

```bash
mix run -e 'alias Jido.AI.Actions.Reasoning.RunStrategy; {:ok, result} = Jido.Exec.run(RunStrategy, %{strategy: :cot, prompt: "Evaluate two rollout options and recommend one with a fallback.", options: %{llm_timeout_ms: 20_000}, timeout: 30_000}); IO.inspect(result, label: "run_strategy")'
```
