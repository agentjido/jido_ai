# Choose a reasoning method

Reasoning selects the sequence of model and tool work inside an AI profile.
It does not change how an application starts an Agent or asks a question.
Start with the profile's default for one answer. Select `:react` when the model
must choose a tool, read its output, and continue. Choose another method only
when its shape of work solves a specific problem.

```elixir
ai :assistant do
  model "openai:gpt-4o-mini"
  reasoning :react

  tools do
    action MyApp.Lookup, as: :lookup
  end
end
```

Linear methods such as Chain of Thought and Chain of Draft shape one line of
reasoning in one structured model call. Tree generates alternatives, evaluates
and selects them, then synthesizes an answer in three calls. Graph builds
thought nodes and relationships, then synthesizes from that graph in two calls.
TRM runs one bounded draft, critique, and revision cycle in three calls.
Adaptive selection chooses a method by local policy. These methods do not all
expose the same tool behavior or reasoning detail. Read each method's contract
before you replace ReAct in a tool agent.

All built-in methods accept the same base request fields: `input`,
`instructions`, `model`, `options`, `prompt_cache`, `context`, and `limits`.
ReAct adds fields for tools, review, streaming, and its output schema.

All methods also return the same base result fields. `status` reports whether
the request completed, was blocked, or failed. `reason_code` gives a stable
cause. `reason` gives readable detail. `reasoning` contains method-specific
data or `nil`. The Session Thread gets one versioned `:ai_request_outcome`
entry with the same result and run summary. An external evaluation system can
use this entry without adding evaluation policy to Jido AI.

Compare methods on a measured task: quality of final result, provider calls,
latency, and whether tool evidence reaches later calls. Do not infer quality
from a method name. Keep the Agent's public route stable while changing the
method so your comparison measures the method rather than a different
application path.

The [reasoning examples](../../examples/09_reasoning/README.md) cover current
methods. Run [Compare reasoning methods](../livebooks/reasoning_methods.livemd)
for a small linear comparison. The notebook's mock responses prove routing
and result handling, not that one method is smarter than another. Continue
with the [turn sequence](09_turn_sequence.md).
