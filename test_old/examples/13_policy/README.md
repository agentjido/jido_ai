# Policy example tests

These tests run the source examples in `examples/13_policy`. They use the
`:example` tag and do not run with the normal `mix test` command.

| Feature guide | Tests |
| --- | --- |
| [13_01_quota](../../../examples/13_policy/13_01_quota/README.md) | [13_01_quota_test.exs](13_01_quota/13_01_quota_test.exs) |

Run this group from the repository root:

```sh
mix test test/examples/13_policy --include example --seed 0
```

See [all example tests](../README.md).
