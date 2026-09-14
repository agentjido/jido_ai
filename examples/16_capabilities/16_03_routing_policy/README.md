# ModelRouting and Policy

The [Agent example](agent.ex)
combines ModelRouting, Policy, a native AI profile and an ordinary route. A
second definition uses Chat and CoT capability routes. The
[example suite](../../../test/examples/16_capabilities/16_03_routing_policy/16_03_routing_policy_test.exs)
has 21 cases. They use real core preparation, Actions, Flows and Agent commits.
All model requests use the shared HTTP mock and ReqLLM.

```sh
mix test test/examples/16_capabilities/16_03_routing_policy/16_03_routing_policy_test.exs --include example --seed 0
```

## Declaration and state

Use the existing Plugin declaration inside `agent do`:

```elixir
plugin Jido.AI.Plugins.ModelRouting,
  config: [routes: %{"case.review" => :capable}]

plugin Jido.AI.Plugins.Policy,
  config: [mode: :enforce, max_delta_chars: 4000,
           block_on_validation_error: true]
```

Both Plugins retain their module names, catalog functions, state keys and
schema functions. Use keyword configuration. Core initializes state with
`state_spec/1` and prepares commands with `prepare/2`.
Both Plugins have empty Action catalogs and do not add routes.

Preparation reads committed Plugin state from the core Command. Caller context
cannot replace that state. Empty restored state uses the declared defaults.
Invalid or duplicate options fail when the Agent definition is made. These
checks now share one small option validator with Chat, Planning and reasoning
Plugins. Policy uses Zoi defaults, including for an explicit `nil` value.

## Model selection

An explicit nonempty request model wins. Otherwise an exact route wins, followed
by a matching wildcard. A `nil` exact value permits wildcard fallback. Overlapping
wildcards use lexical order. `*` does not cross a dot in the Signal type.

The built-in routes retain capable for `chat.message`, fast for `chat.simple`
and `chat.complete`, thinking for `chat.generate_object`, embedding for
`chat.embed`, and reasoning for `reasoning.*.run`. Configured routes extend or
replace those entries. Provider requests prove the selected model for each
Chat generation operation and embeddings.

Known string Action keys are converted before schema validation. If both key
forms exist, the canonical atom key wins. This also prevents an empty string
model key from replacing a model inserted by ModelRouting. Invalid models fail
before provider work and preserve committed Agent state.

Native AI requests use the same model choice. One shared helper reads the
declared core route target and its fixed profile ID. It merges route input with
Signal data. Payload `profile_id` cannot select a different declared profile.
The request model replaces the selected profile's primary reasoning model for
that request only. Tests cover both one-Turn and session requests on a custom
route, an explicit override, and a later request with the declared default.

## Policy behavior

Enforce mode with blocking enabled returns this error through the core call:

```elixir
{:error, %{
  type: :policy_violation,
  message: "request blocked by policy",
  details: %{request_id: request_id, signal_type: signal_type},
  retryable?: false
}}
```

The rejected request makes no provider call and commits no state. It does not
change the Signal type to `ai.request.error` or execute that route. Consumers
must handle the returned error. This is the rejection change in the v3 plan.
Existing correlation fields are retained; a missing ID is generated.

Monitor mode or `block_on_validation_error: false` permits the same input.
Both still normalize model/tool result envelopes and sanitize text deltas.
Successful two- and three-element result tuples retain their values and effects.
Malformed envelopes use the shared error format. Complete typed image content
parts survive delta preparation; text length limits do not truncate image data.

Native AI requests check the query selected by the actual route, including
declared input defaults and custom Signal names. A harmless `prompt` field
cannot mask a rejected native `query`. Multimodal query checks read text parts
and leave image parts intact. Ordinary domain routes keep their own input
contract.

## Mock protocol and evidence limits

The same mock now responds to a forced structured-output tool with tool-call
data. Its existing object script also works with JSON response format. A default
mock contract test checks non-streamed and streamed forced-tool decoding and
usage through ReqLLM. There is no separate object provider stub.

Eleven native Plugin contract tests under the existing root test paths supplement
the 21 example cases. Integration exclusion is not passing evidence.
The native model tests use direct core calls followed by session await where
needed. They do not prove all public `ask`/`submit` option forms, a provider
switch within one active loop, Fireworks/xAI formats, or WebSocket continuation.
Those PR 295 requirements remain open. The typed image case proves Policy
preparation, not the complete provider-generated image stream from PR 340.

This example does not cover dynamic configuration, durable recovery, or every
provider transport format.
