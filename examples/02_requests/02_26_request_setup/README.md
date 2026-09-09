# 02_26: Declared and request options

The [Agent examples](agent.ex)
use native `agent do` profiles in Session and direct Turn mode. Two more modules
use the public Agent macro with a string-key `llm_opts` map and a model alias
that is set at runtime. Each mode runs buffered and streamed requests.
The [six example cases](../../../test/examples/02_requests/02_26_request_setup/02_26_request_setup_test.exs)
use the shared HTTP/SSE server and actual ReqLLM execution.

```sh
mix test test/examples/02_requests/02_26_request_setup/02_26_request_setup_test.exs --include example
```

Each case sends three requests. The first changes temperature and retains the
declared token limit and header. The second retains those declared defaults
with no effective override. The third replaces the headers option. The selected
request cannot change the Agent definition or later request defaults. All
result states remain portable.

Session cases merge declared HTTP options, runtime context and explicit request
HTTP options in that order. An empty request keyword list keeps existing
options. Direct Turn cases use the same preparation helper for declared and
runtime options. Header lists are option values: a supplied list replaces the
previous list; this is not a merge of individual header entries.

Buffered Session cases also run a request-scoped Req adapter callback. It adds
an actual header and is absent from the next request. ReqLLM owns its streaming
Finch path and does not invoke this custom Req adapter there. The streamed
cases check actual headers, model values, SSE events and final results. These
examples do not claim streaming custom-adapter support.

The shared option-name normalizer accepts the retained string-key map without
creating atoms for unknown names. It does not resolve aliases during Agent
compilation. Provider option values are normalized after the request resolves
its model. The public examples compile before their alias is installed by test
setup and then execute actual HTTP calls.

The [root case map](../../../docs/v3-spike/react-setup-test-transfer.md) transfers
24 old ReAct setup cases. Prepared-request controls retain their exact option
checks, including provider fields that are not valid for every wire protocol.
Those controls deliberately stop before a model call. These HTTP examples add
separate execution proof. Remaining provider-specific and compatibility gates
are still required; no history row is closed by this example.
