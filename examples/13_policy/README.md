# Policy examples

Read the table from top to bottom for the learning order. Gaps in the IDs
are intentional; the remaining examples keep their published IDs.

These checked examples use the current Jido AI public contract. Each feature
keeps its source and detailed guide in one folder. Its tests live in the
matching `test/examples/13_policy` folder.

| Feature | Guide | Tests |
| --- | --- | --- |
| `13_01_quota` | [Quota accounting and Agent admission](13_01_quota/README.md) | [13_01_quota_test.exs](../../test/examples/13_policy/13_01_quota/13_01_quota_test.exs) |

Run this group from the repository root:

```sh
mix test test/examples/13_policy --include example --seed 0
```

See the [full example catalog](../README.md).
