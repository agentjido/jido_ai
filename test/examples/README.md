# Example tests

Runnable source and feature notes live in the root
[example catalog](../../examples/README.md). Test folders follow that catalog.
Every test uses the `:example` tag, directly or through
`JidoAI.Examples.Case`.

```sh
mix test                                      # Excludes examples
mix examples --seed 0                        # Runs all examples
mix test test/examples/09_reasoning --include example --seed 0
```

Keep each feature assertion in one suite. Do not copy an example assertion
into the core regression suite.
