# Callable reasoning through v3 Exec

The [Agent example](agent.ex)
and [21 example cases](../../../test/examples/09_reasoning/09_14_callable_reasoning/09_14_callable_reasoning_test.exs)
port `Jido.AI.Actions.Reasoning.RunStrategy` to the shared v3 runtime. The Action
supports CoD, CoT, AoT, ToT, GoT, TRM and Adaptive. Each method runs through direct
`Jido.Exec.run/4` and an ordinary Agent Action. The outer Agent retains its domain
state and commits the returned result through the normal core contract.

```elixir
Jido.Exec.run(
  Jido.AI.Actions.Reasoning.RunStrategy,
  %{strategy: :cot, prompt: "Explain this result", timeout: 5_000},
  %{jido: MyApp.Jido}
)
```

`context.jido` selects an existing host runtime. Without it, the Action uses a
standalone core Agent. It does not start `Jido.AI.InternalReasoningRunner`.
Each call owns one linked Agent and its Session. It uses the existing Profile,
Authoring lowerer, reasoning Flow, model operations and Session implementation.
No new reasoning executor or mock server is present.

The factory places the requested method, model, and options in a validated
profile before instantiation. Cancellation of the calling Exec stops the Agent,
its Session, and the active provider connection. Normal cleanup preserves the
Action result.
Repeated and concurrent calls use separate request/run IDs and leave the shared
host runtime alive. The concurrency case uses two barriers on the same mock.

The public result retains `strategy`, `status`, `output`, `usage` and
`diagnostics`. AoT and ToT keep complete structured outputs. The tests compare
the actual answers, usage, candidates and diagnostics; per-run node IDs and
durations are allowed to differ. TRM defaults permit all five supervision
cycles: 15 model calls and 225 mock tokens. Its result is the latest completed
improvement, while retained diagnostics keep the highest reviewed answer. A GoT depth/node override produces
one actual call. Top-level values retain precedence over nested method options.
Existing Plugin-state defaults and explicit `provided_params` context still
control timeout, model and option precedence.

Provider failure returns a failure envelope. A later failed phase keeps prior
usage and method diagnostics. AoT failure cannot become a successful result just
because its structured output exists. ToT evaluation failure keeps its method
result and evaluated tree state; unevaluated thoughts are not installed nodes.
A caller wait timeout attempts Session cancellation before it reads the final
record and stops the private Agent. A commit observed after a wait timeout can
still use the existing recovered-success path. Unknown external work is not
replayed.

The `diagnostics.snapshot_*` values come from the canonical V3 request snapshot.
Current request metadata and method diagnostics replace private worker fields.
The Action retains its name, input schema, category, tags, and contract version.

The factory removes parent Agent state and private AI execution bindings from
caller context before admission. Trusted provider options use the existing
`ai.assistant.options` context binding. Model transport runs through the same
mock used by the other examples. This does not yet prove nested AI-tool budget
aggregation or complete provider-option parity.

Capability Plugin declarations, CLI dispatch, durable recovery, and release
gates are outside this focused Action example.

The Planning port adds a current-Agent-struct defaults case. Callable reasoning
now reads that state with map-safe access; configured timeout and prompt defaults
reach the actual model request.
