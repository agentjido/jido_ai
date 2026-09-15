# Example tests

Runnable source and feature notes live in the root
[example catalog](../../examples/README.md). Test folders follow that catalog.
Every test uses the `:example` tag, directly or through
`JidoAI.Examples.Case`.

```sh
mix test                                      # Excludes examples
mix examples --seed 0                          # Runs all example tests
mix test test/examples/09_reasoning --include example --seed 0
```

The numeric-string usage regression runs without skips. The pinned ReqLLM
revision includes the fix for [issue #1008](https://github.com/agentjido/req_llm/issues/1008).

The catalog tests check guide links and sections, run-command paths, folder IDs,
matching test groups, and skipped tests. They also reject process barriers and
test observers in application example source. They run with the examples.

The fresh-VM checkpoint test runs normally but is omitted under coverage, where
instrumentation changes code fingerprints. Run the normal suite as well.

Runtime lesson tests run serially. They check application behavior within the
declared time budgets; they are not load tests. Pure value and catalog checks
can run asynchronously.

Keep each feature assertion in one suite. Do not copy an example assertion
into the core regression suite.
