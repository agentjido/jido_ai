# Skills System

You need to package reusable instructions/capabilities and load them safely.

After this guide, you can load skill files, register specs, render prompts, and handle common runtime failures.

## Core Contracts

- `Jido.AI.Skill`
- `Jido.AI.Skill.Spec`
- `Jido.AI.Skill.Loader`
- `Jido.AI.Skill.Registry`
- `Jido.AI.Skill.Prompt`
- `mix jido_ai.skill`

## Lifecycle: Load, Register, Resolve, Retire

```elixir
{:ok, spec} = Jido.AI.Skill.Loader.load("priv/skills/code-review/SKILL.md")
{:ok, _pid} = Jido.AI.Skill.Registry.start_link()
:ok = Jido.AI.Skill.Registry.register(spec)

{:ok, loaded} = Jido.AI.Skill.resolve(spec.name)
body = Jido.AI.Skill.body(loaded)

prompt = Jido.AI.Skill.Prompt.render([spec.name], include_body: false)

:ok = Jido.AI.Skill.Registry.unregister(spec.name)
:ok = Jido.AI.Skill.Registry.clear()
```

Registry lifecycle guarantees:
- explicit startup via `start_link/1`
- lazy startup via `ensure_started/0` used by public APIs
- safe unregister/clear operations for runtime teardown

## CLI Surface + Error Handling

```bash
mix jido_ai.skill list priv/skills
mix jido_ai.skill show priv/skills/code-review/SKILL.md --body
mix jido_ai.skill validate priv/skills --strict
mix jido_ai.skill validate priv/skills --json
```

CLI failure behaviors:
- `mix jido_ai.skill list` with no paths prints usage help
- `mix jido_ai.skill validate` with no paths prints usage help
- unknown commands print `mix jido_ai.skill` help guidance
- `--strict` raises when any skill fails validation (non-zero exit)

## Failure Modes

### Invalid frontmatter or schema

Symptom:
- loader returns parse/validation error (`NoFrontmatter`, `InvalidYaml`, `MissingField`, `InvalidName`)

Fix:
- ensure YAML frontmatter contains required fields
- validate with `mix jido_ai.skill validate ...` before loading in runtime

### Lookup failure after registration workflow

Symptom:
- `Jido.AI.Skill.resolve/1` or `Registry.lookup/1` returns `NotFound`

Fix:
- ensure skills were registered into the current runtime registry instance
- confirm normalized names (kebab-case) match lookup keys

## Defaults You Should Know

- skill registry stores by skill name
- `body_ref` can be inline or file-backed
- allowed tools are normalized to string names
- `Prompt.render/2` ignores unresolved skills and renders only valid specs

## Demo + Examples

Run the end-to-end demo script:

```bash
mix run lib/examples/scripts/demo/skills_runtime_foundations_demo.exs
```

Prerequisites:
- run from project root
- keep `priv/skills/code-review/SKILL.md` available (checked by script)

If required skill files are missing, the demo prints a skip message and continues.

## When To Use / Not Use

Use skills when:
- you need reusable instruction packs across agents

Do not use skills when:
- static prompts in agent config are sufficient

## Next

- [Plugins And Actions Composition](plugins_and_actions_composition.md)
- [Configuration Reference](configuration_reference.md)
- [CLI Workflows](../user/cli_workflows.md)
