# Thread Context And Message Projection

You need deterministic conversation state and explicit message projection to LLM input format.

After this guide, you can build and inspect thread history using `Jido.AI.Thread`.

## Build A Thread

```elixir
alias Jido.AI.Thread

thread =
  Thread.new(system_prompt: "You are concise.")
  |> Thread.append_user("Hello")
  |> Thread.append_assistant("Hi")
  |> Thread.append_user("Summarize this chat")
```

## Project To Messages

```elixir
messages = Thread.to_messages(thread)
# [%{role: :system, ...}, %{role: :user, ...}, ...]

recent_messages = Thread.to_messages(thread, limit: 2)
```

## Import Existing Messages

```elixir
raw = [
  %{role: "user", content: "Question"},
  %{role: "assistant", content: "Answer"}
]

thread = Thread.new() |> Thread.append_messages(raw)
```

Use `Jido.AI.Text.extract_text/1` when normalizing diverse provider response shapes.

## Failure Mode: Unexpected Missing Context

Symptom:
- assistant ignores previous turns

Fix:
- verify you append both user and assistant/tool entries
- avoid too-small `limit` values during projection
- inspect with `Thread.debug_view/2` or `Thread.pp/1`

## Defaults You Should Know

- Entries are stored reversed internally for append speed
- `Thread.to_messages/2` reorders to chronological output
- `limit: nil` includes full thread

## When To Use / Not Use

Use this when:
- you need explicit control over message windows
- you need import/export-friendly thread format

Do not use this when:
- strategy internals already manage conversation state for your use case

## Next

- [Streaming Workflows](streaming_workflows.md)
- [First Agent](first_react_agent.md)
- [Configuration Reference](../developer/configuration_reference.md)
