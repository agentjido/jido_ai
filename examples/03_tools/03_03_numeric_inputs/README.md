# 03_03: Numeric tool inputs

The [Agent, Action and Flow](agent.ex)
and [four example cases](../../../test/examples/03_tools/03_03_numeric_inputs/03_03_numeric_inputs_test.exs)
use the shared HTTP mock. The model returns numeric strings. The real tool
receives integers and floats, and its result reaches the next model request.

```sh
mix test --include example test/examples/03_tools/03_03_numeric_inputs/03_03_numeric_inputs_test.exs
```

The same input adapter serves `Turn.normalize_params/2`, direct Turn execution,
and Session tool admission. It converts complete integer and float strings for
numeric schema fields. It also converts an integer to a float for a float field.
Zoi object fields, default values and array items retain their schemas. Missing
fields remain missing until the real Action or Flow validator applies defaults.

Each tool form has a success case and a failed-batch case. A malformed numeric
argument in the second call prevents both calls from starting. It leaves domain
state unchanged and stores the request failure. A successful call runs once,
stores its typed result, sends correlated JSON to the model, and clears live
work at completion.

The root tests also cover invalid integer text, nil, fractional integers,
unknown keys, explicit atom-key precedence, numeric text in string fields,
timeouts and exception logging. General request and Signal input validation
remains strict. This adapter does not enable general scalar coercion.

See the [root tool repair record](../../../docs/v3-spike/tool-input-repair.md)
for the retained test counts and scope.
