# AoT root test transfer

All 18 root cases remain in the default suite: 11 former Strategy cases and
7 public wrapper cases. They use native Agent, Action, Flow and Session APIs
with `Jido.AI.Test.MockLLM`. The shared test helper starts the local Jido instance;
it does not add another provider mock or runtime. No case is skipped.

The baseline is `fc5bc1434ddb69493fe8a68443f03bc6a198c5a2`. Each old test
below has a native replacement. The removed action names and Strategy state are
replaced by typed admission/cancellation Actions, profile route bindings, and
Session inspection. Unknown routes fail. The public method is
`:algorithm_of_thoughts`.

The held HTTP/SSE cases prove worker ownership and busy-request correlation.
The parser case keeps the original number puzzle and its 13-token usage check.
It also checks the search metrics and full raw response. Custom profile, search
style, temperature, and token limits are checked on the actual provider request.
Result completion stores the same full value in the request and public state.

As with [CoT and CoD](linear-test-transfer.md), rejected requests return an error
and a correlated caller-stream event. They do not overwrite active request state.
This is the documented replacement for the old request-error Strategy hook.

## Case map

### `test/jido_ai/strategy/algorithm_of_thoughts_test.exs`

| Old case | Native replacement |
| --- | --- |
| initializes machine state and config | [initializes the native profile and default generation settings](../../test/jido_ai/strategy/algorithm_of_thoughts_test.exs) |
| accepts custom AoT options | [custom AoT profile search style and generation reach the provider](../../test/jido_ai/strategy/algorithm_of_thoughts_test.exs) |
| returns specs for strategy actions | [native Actions validate admission and cancellation inputs](../../test/jido_ai/strategy/algorithm_of_thoughts_test.exs) |
| routes expected AoT signals | [AoT query routes select the method and model observations stay read only](../../test/jido_ai/strategy/algorithm_of_thoughts_test.exs) |
| start instruction emits LLMStream directive | [start owns a streaming call with a correlated request and prompt](../../test/jido_ai/strategy/algorithm_of_thoughts_test.exs) |
| busy second start emits request error directive with request id correlation | [a busy second start returns its own request ID](../../test/jido_ai/strategy/algorithm_of_thoughts_test.exs) |
| request_error instruction stores lifecycle rejection metadata | [rejection metadata does not overwrite the active AoT request](../../test/jido_ai/strategy/algorithm_of_thoughts_test.exs) |
| llm result instruction transitions to completed with parsed output | [model completion stores the parsed puzzle result and usage](../../test/jido_ai/strategy/algorithm_of_thoughts_test.exs) |
| returns idle snapshot for new agent | [snapshot of a new AoT Agent has no result or live request](../../test/jido_ai/strategy/algorithm_of_thoughts_test.exs) |
| returns running snapshot after start | [snapshot of running work keeps the selected long profile](../../test/jido_ai/strategy/algorithm_of_thoughts_test.exs) |
| returns expected action atoms | [public method selection replaces private Strategy action atoms](../../test/jido_ai/strategy/algorithm_of_thoughts_test.exs) |

### `test/jido_ai/aot_agent_test.exs`

| Old case | Native replacement |
| --- | --- |
| creates agent module with expected name | [creates agent module with expected name](../../test/jido_ai/aot_agent_test.exs) |
| defines explore and explore_sync helpers | [defines explore and explore_sync helpers](../../test/jido_ai/aot_agent_test.exs) |
| uses AlgorithmOfThoughts strategy | [selects AlgorithmOfThoughts in the native profile](../../test/jido_ai/aot_agent_test.exs) |
| passes custom AoT options to strategy | [passes custom AoT options to strategy](../../test/jido_ai/aot_agent_test.exs) |
| uses expected defaults when not provided | [uses expected defaults when not provided](../../test/jido_ai/aot_agent_test.exs) |
| on_before_cmd marks request as failed on aot_request_error | [busy admission keeps the active request and sends correlated failure](../../test/jido_ai/aot_agent_test.exs) |
| on_after_cmd finalizes pending request on delegated worker completion | [completion stores the full result in both request and public state](../../test/jido_ai/aot_agent_test.exs) |

## Validation

All 18 targeted cases passed in 2.5 seconds. These files had 14 failures in the
prior full root run. The case count is unchanged. This pass required no AoT
production change. See the [root checkpoint](root-package-checkpoint.md) for the
full package result. No history row or API baseline was changed.

Log: `/tmp/jido-ai-v3-aot-root-test-01.log`.
