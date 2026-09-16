# Test your AI Agent

Test the authored Agent through AgentServer and the generated `ask` helpers.
Keep real Jido Flow, Action validation, ReqLLM transport, and state commit in
the test. Replace only the remote model service with
`Jido.AI.Test.MockLLM`. A script can return text, an object, tool calls, an
HTTP error, or a held response.

```elixir
{:ok, mock} = Jido.AI.Test.MockLLM.start_link(script: [
  %{reply: {:text, "Ready"}}
])

context = %{
  ai: %{assistant: %{options: Jido.AI.Test.MockLLM.options(mock)}}
}

{:ok, answer} = MyApp.Agent.ask_sync(server, "Help", context: context)
%{remaining: [], unexpected: []} = Jido.AI.Test.MockLLM.report(mock)
```

For each stable Agent, prove its main success result and one important
failure. Assert the committed domain field, not only the returned text. If a
tool sequence matters, inspect captured model requests to prove that the
next call received the prior tool result. If a request is meant to fail,
assert that domain state remains valid and the request has a terminal status.
Use a mock barrier for steering or cancellation; do not rely on `sleep`.

Keep unit tests for detailed edge matrices and example tests for one clear
integration claim. The [authoring suite](../../test/authoring/README.md)
checks the DSL surface. The [example suite](../../examples/README.md) checks
runtime behavior. Run a small live-provider check only after deterministic
tests pass; a live model's exact wording and tool choices are not stable test
assertions.

Every Livebook in this guide set uses the same mock/live choice. Run the
Livebook in mock mode first, then switch to live to explore provider behavior
without changing the Agent definition.
