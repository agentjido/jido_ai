# Skills examples

These checked examples use the current Jido AI public contract. Each feature
keeps its source and detailed guide in one folder. Its tests live in the
matching `test/examples/18_skills` folder.

| Feature | Guide | Tests |
| --- | --- | --- |
| `18_01_skill_runtime` | [18_01: Skill activation and resource access](18_01_skill_runtime/README.md) | [18_01_skill_runtime_test.exs](../../test/examples/18_skills/18_01_skill_runtime/18_01_skill_runtime_test.exs) |
| `18_02_skill_authoring` | [18_02: Automatic skill authoring](18_02_skill_authoring/README.md) | [18_02_skill_authoring_test.exs](../../test/examples/18_skills/18_02_skill_authoring/18_02_skill_authoring_test.exs) |

Run this group from the repository root:

```sh
mix test test/examples/18_skills --include example --seed 0
```

See the [full example catalog](../README.md).
