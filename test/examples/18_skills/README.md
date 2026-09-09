# Skills example tests

These tests run the source examples in `examples/18_skills`. They use the
`:example` tag and do not run with the normal `mix test` command.

| Feature guide | Tests |
| --- | --- |
| [18_01_skill_runtime](../../../examples/18_skills/18_01_skill_runtime/README.md) | [18_01_skill_runtime_test.exs](18_01_skill_runtime/18_01_skill_runtime_test.exs) |
| [18_02_skill_authoring](../../../examples/18_skills/18_02_skill_authoring/README.md) | [18_02_skill_authoring_test.exs](18_02_skill_authoring/18_02_skill_authoring_test.exs) |

Run this group from the repository root:

```sh
mix test test/examples/18_skills --include example --seed 0
```

See [all example tests](../README.md).
