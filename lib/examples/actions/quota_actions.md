# Quota Action Snippets

Run these from the repository root.

## GetStatus Action

```bash
mix run -e 'alias Jido.AI.Actions.Quota.GetStatus; context = %{plugin_state: %{quota: %{scope: "assistant_ops", window_ms: 60_000, max_requests: 50, max_total_tokens: 20_000}}}; {:ok, result} = Jido.Exec.run(GetStatus, %{}, context); IO.inspect(result, label: "quota_status")'
```

## Reset Action

```bash
mix run -e 'alias Jido.AI.Actions.Quota.Reset; {:ok, result} = Jido.Exec.run(Reset, %{scope: "assistant_ops"}); IO.inspect(result, label: "quota_reset")'
```
