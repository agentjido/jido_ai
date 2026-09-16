# Livebook development checks

Run these notebooks from the `jido_ai` checkout with sibling V3 `jido`,
`jido_action`, and `jido_signal` folders. Each notebook has one editable
`backend = :mock` line. Mock mode needs no API key. Live mode uses the
declared OpenAI model and needs `OPENAI_API_KEY`.

Livebook's local dev endpoints open and sync a notebook file. Enable them in
Livebook Settings. They do not evaluate cells. For example:

```sh
curl -X POST http://127.0.0.1:32123/dev/open \
  -H 'content-type: application/json' \
  -d '{"file":"/absolute/path/to/jido_ai/guides/livebooks/first_answer.livemd"}'
```

Use `/dev/sync` with the same JSON body after an edit. Evaluate cells in
Livebook, or run the checked cells in order with:

```sh
elixir guides/livebooks/verify.exs guides/livebooks/first_answer.livemd
```

Run the verifier in a new VM for each notebook. It evaluates every Elixir
cell in order and exits on a failed match or exception. It does not test
Livebook's UI. The dev endpoint checks file loading; the verifier checks
MockLLM behavior. A first `Mix.install` can take time while it builds the
local dependencies.
