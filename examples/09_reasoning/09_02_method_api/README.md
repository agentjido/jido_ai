# 09_02: Linear Method APIs

This example lowers one Agent definition with separate Chain of Thought and
Chain of Draft profiles. Both profiles use the shared Session runtime and keep
their results separate.

Use `method/0` to select a method in a profile. Use `get_steps/2`,
`get_conclusion/2`, and `get_raw_response/2` to inspect committed results.
There is no Strategy adapter or separate Machine API.

```sh
mix test test/examples/09_reasoning/09_02_method_api --include example --seed 0
```
