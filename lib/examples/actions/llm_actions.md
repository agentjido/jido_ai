# LLM Action Snippets

Run these from the repository root with provider credentials configured.

## Chat Action

```bash
mix run -e 'alias Jido.AI.Actions.LLM.Chat; {:ok, result} = Jido.Exec.run(Chat, %{prompt: "Summarize Elixir in one sentence."}); IO.inspect(result, label: "chat")'
```

## Complete Action

```bash
mix run -e 'alias Jido.AI.Actions.LLM.Complete; {:ok, result} = Jido.Exec.run(Complete, %{prompt: "The key feature of OTP is"}); IO.inspect(result, label: "complete")'
```

## Embed Action

```bash
mix run -e 'alias Jido.AI.Actions.LLM.Embed; {:ok, result} = Jido.Exec.run(Embed, %{texts_list: ["elixir", "erlang"], model: :embedding}); IO.inspect(result, label: "embed")'
```

## GenerateObject Action

```bash
mix run -e 'alias Jido.AI.Actions.LLM.GenerateObject; schema = Zoi.object(%{title: Zoi.string(), confidence: Zoi.float()}); {:ok, result} = Jido.Exec.run(GenerateObject, %{prompt: "Return a JSON object with title and confidence for this note: Jido AI roadmap", object_schema: schema}); IO.inspect(result, label: "generate_object")'
```
