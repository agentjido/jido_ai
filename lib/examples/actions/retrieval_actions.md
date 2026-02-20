# Retrieval Action Snippets

Run these from the repository root.

## UpsertMemory Action

```bash
mix run -e 'alias Jido.AI.Actions.Retrieval.UpsertMemory; {:ok, result} = Jido.Exec.run(UpsertMemory, %{namespace: "weather_ops", id: "seattle_weekly", text: "Seattle mornings are cooler this week with intermittent rain.", metadata: %{source: "weekly_summary", region: "pnw"}}); IO.inspect(result, label: "upsert_memory")'
```

## RecallMemory Action

```bash
mix run -e 'alias Jido.AI.Actions.Retrieval.RecallMemory; {:ok, result} = Jido.Exec.run(RecallMemory, %{namespace: "weather_ops", query: "seattle rain outlook", top_k: 2}); IO.inspect(result, label: "recall_memory")'
```

## ClearMemory Action

```bash
mix run -e 'alias Jido.AI.Actions.Retrieval.ClearMemory; {:ok, result} = Jido.Exec.run(ClearMemory, %{namespace: "weather_ops"}); IO.inspect(result, label: "clear_memory")'
```
