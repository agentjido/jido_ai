# 02_24: Stream usage sources

The [native Agents](agent.ex)
use `agent do`, one AI profile, an explicit model, a real Action tool and a
Session route. One Agent records deltas; the other disables them. The
[tests](../../../test/examples/02_requests/02_24_stream_usage/02_24_stream_usage_test.exs) run the same
cases through native requests and the public standalone ReAct adapter.
All provider requests use the shared HTTP/SSE mock.

```sh
mix test test/examples/02_requests/02_24_stream_usage/02_24_stream_usage_test.exs --include example
```

There are eight cases. Four pass: each API preserves an explicit provider zero
and combines two model calls after cumulative stream updates. The tool case
sends repeated and decreasing usage records in one call, then completes a
second call. It checks per-call counts of 5 and 3, a request total of 8, real
Action execution, correlated tool JSON, terminal state and the standalone token.
Delta capture is disabled for the cumulative case.

Four cases remain as upstream regression checks. They supply complete OpenAI usage
fields with numeric-string values (`"3"`, `"1"`, `"4"`). ReqLLM 1.22 raises
`:badarith` in its stream server before AI receives the usage chunk. Each API
must preserve the counts with delta capture both enabled and disabled. These
cases have `:upstream_failure` and `:skip` tags, so `mix examples` skips them.
Run them explicitly after a ReqLLM update:

```sh
mix test test/examples/02_requests/02_24_stream_usage/02_24_stream_usage_test.exs \
  --include example --include skip
```

The original runner regression used an already-decoded metadata chunk with
only input and output strings. The AI fallback now preserves that accepted
input and derives total 4. Separate [source-boundary tests](../../../test/jido_ai/usage/stream_test.exs)
prove source priority, zero values, independent maxima and cleanup. This is
not proof that the failing provider-wire cases work.

A missing total field has a different problem in the OpenAI decoder: it
replaces the incomplete usage map with zeros before AI receives it. The
fallback does not override a nonempty processed zero. Provider format repair
must happen at the decoder boundary, with explicit-zero behavior retained.
See the [port record](../../../docs/v3-spike/stream-usage-port.md).

The normal example suite reports these four cases as excluded until the
dependency fix is available.
