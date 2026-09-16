# Add a tool and ReAct

Use ReAct when a model must choose an operation, read its result, and then
continue. The tool is a Jido Action or Flow. The AI runtime validates tool
input and runs the declared target; the model does not call an Elixir function
directly.

Add these blocks to an `ai :assistant do` definition:

```elixir
reasoning :react

tools do
  action MyApp.Multiply, as: :multiply
end

controls do
  timeout 30_000
  max_iterations 4
  max_model_calls 4
  max_tool_calls 3
end
```

The Action must have a stable input schema and a result that the model can
use. If the operation has several dependent steps, declare a Flow tool and
make its output explicit. Put business rules in the Action or Flow, not in a
prompt that asks the model to do arithmetic or enforce policy.

One ReAct round can be: model requests `multiply`, Jido validates and runs the
Action, the tool result enters the request Context, and the model receives
that result on its next call. A final answer comes only after the model stops
requesting tools. The three limits above protect different resources: overall
reasoning rounds, provider calls, and tool calls. A timeout bounds elapsed
time. Set all of them for an agent that can use tools.

Read the [three-round Agent](../../examples/01_authoring/01_02_tool_flow/multi_round_agent.ex)
and its [behavior test](../../test/examples/01_authoring/01_02_tool_flow/multi_round_test.exs).
The test checks that each later model call contains the prior tool result. Then
run [Three tool rounds](../livebooks/three_tool_rounds.livemd) and inspect the
captured model requests. A live model may choose a different sequence; the
mock script proves the exact contract.

Next, decide [where the answer goes](03_results_and_state.md).
