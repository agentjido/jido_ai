# Structured results and repair

Use a result schema when downstream code needs fields rather than free text.
The schema checks the model output before it is mapped into Agent state.
`max_repairs` allows a bounded retry with validation feedback. A repair is a
new model call, so the model-call limit must include it.

```elixir
ai :assistant do
  model "openai:gpt-4o-mini"

  controls do
    timeout 10_000
    max_model_calls 2
  end

  result(Zoi.object(%{answer: Zoi.string() |> Zoi.min(1)}),
    into: :answer,
    max_repairs: 1
  )
end
```

Here the first invalid object can produce one repair request. A second invalid
object fails the request. The prior domain answer stays in place. A provider
error is not a schema error, so it does not start schema repair. Validation
proves shape, not truth; an answer can satisfy the schema and still be wrong.

Use the smallest schema that protects the next consumer. Do not add a broad
map schema only to make output look structured. If the application needs a
business invariant, validate it after shape validation and before commit.
Record the invalid result only when observability policy allows the content.

The [structured-output test](../../test/examples/01_authoring/01_03_structured_output/01_03_structured_output_test.exs)
shows the first invalid object, feedback on the next model request, and the
final valid commit. Run [Break and repair a result](../livebooks/repair_result.livemd)
to see the same sequence. Continue with [reasoning methods](08_reasoning_methods.md).
