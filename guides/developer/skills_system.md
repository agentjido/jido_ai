# Skills System

You need to package reusable instructions/capabilities and load them safely.

After this guide, you can load skill files, register specs, and query skill metadata.

## Core Modules

- `Jido.AI.Skill`
- `Jido.AI.Skill.Spec`
- `Jido.AI.Skill.Loader`
- `Jido.AI.Skill.Registry`

## Load + Register

```elixir
{:ok, spec} = Jido.AI.Skill.Loader.load("priv/skills/code_review/SKILL.md")
{:ok, _pid} = Jido.AI.Skill.Registry.start_link()
:ok = Jido.AI.Skill.Registry.register(spec)

{:ok, loaded} = Jido.AI.Skill.resolve(spec.name)
body = Jido.AI.Skill.body(loaded)
```

## CLI Support

```bash
mix jido_ai.skill list priv/skills
mix jido_ai.skill show priv/skills/code_review/SKILL.md --body
mix jido_ai.skill validate priv/skills --strict
```

## Failure Mode: Invalid Skill Frontmatter

Symptom:
- loader returns parse/validation error

Fix:
- ensure YAML frontmatter contains required fields
- validate with `mix jido_ai.skill validate ...` before loading in runtime

## Defaults You Should Know

- skill registry stores by skill name
- `body_ref` can be inline or file-backed
- allowed tools are normalized to string names

## When To Use / Not Use

Use skills when:
- you need reusable instruction packs across agents

Do not use skills when:
- static prompts in agent config are sufficient

## Next

- [Plugins And Actions Composition](plugins_and_actions_composition.md)
- [Configuration Reference](configuration_reference.md)
- [CLI Workflows](../user/cli_workflows.md)
