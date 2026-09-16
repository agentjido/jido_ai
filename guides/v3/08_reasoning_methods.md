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
reasoning. Tree and graph methods explore several candidates and can cost more
model calls. Adaptive selection chooses a method by policy. These methods do
not all expose the same tool behavior or result shape. Read each method's
contract before replacing ReAct in a tool agent.

Compare methods on a measured task: quality of final result, provider calls,
latency, and whether tool evidence reaches later calls. Do not infer quality
from a method name. Set a budget that fits the selected method. A tree with a
one-call limit is not a useful tree; an unbounded search is not a production
control. Keep the Agent's public route stable while changing the method so
your comparison measures the method rather than a different application path.

The [reasoning examples](../../examples/09_reasoning/README.md) cover current
methods. Run [Compare reasoning methods](../livebooks/reasoning_methods.livemd)
for a small linear comparison. The notebook's mock responses prove routing
and result handling, not that one method is smarter than another. Continue
with the [turn sequence](09_turn_sequence.md).
