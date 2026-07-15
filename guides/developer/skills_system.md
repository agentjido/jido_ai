# Skills System

You need to package reusable instructions/capabilities and load them safely.

After this guide, you can attach trusted Agent Skills with progressive disclosure,
use session-scoped activation, validate skill files, and bound custom discovery.

## Core Contracts

- `Jido.AI.Skill`
- `Jido.AI.Skill.Spec`
- `Jido.AI.Skill.Loader`
- `Jido.AI.Skill.Registry`
- `Jido.AI.Skill.AgentIntegration`
- `Jido.AI.Skill.Prompt`
- `Jido.AI.Actions.Skill.LoadSkill`
- `mix jido_ai.skill`

## Turnkey Agent Integration

`Jido.AI.Agent` can wire the complete progressive-disclosure lifecycle from one
option. Because project skills are executable instructions, enabling standard
root discovery is an explicit trust decision:

```elixir
defmodule MyApp.SupportAgent do
  use Jido.AI.Agent,
    name: "support_agent",
    tools: [MyApp.Search],
    system_prompt: "You are a support agent.",
    agent_skills: true
end
```

This discovers `.agents/skills/` and `~/.agents/skills/`, appends only the compact
name/description catalog to the system prompt, adds
`Jido.AI.Actions.Skill.LoadSkill` to the tools, and makes the resolved specs
available through reserved tool context for that agent. Discovery and catalog
construction happen when the agent module is compiled.

Prefer an explicit list when only particular roots are trusted:

```elixir
use Jido.AI.Agent,
  name: "support_agent",
  tools: [MyApp.Search],
  agent_skills: ["priv/skills", "/opt/my_app/skills"]
```

Discovery options can set tighter bounds:

```elixir
agent_skills: [
  paths: ["priv/skills"],
  trust: true,
  max_depth: 4,
  max_directories: 500,
  exclude_directories: [".git", "node_modules", "deps", "_build"]
]
```

Keyword options must include an explicit `trust` policy. Omitting it rejects
every discovered root; passing a path list directly is the shorthand for
trusting exactly those roots.

Agent Skills integration is disabled by default so an application never starts
trusting repository instructions merely by upgrading a dependency.

## Manual Lifecycle: Load, Register, Resolve, Retire

```elixir
{:ok, spec} = Jido.AI.Skill.Loader.load("priv/skills/code-review/SKILL.md")
{:ok, _pid} = Jido.AI.Skill.Registry.start_link()
:ok = Jido.AI.Skill.Registry.register(spec)

{:ok, loaded} = Jido.AI.Skill.resolve(spec.name)
body = Jido.AI.Skill.body(loaded)

prompt = Jido.AI.Skill.Prompt.render_index([spec.name])

:ok = Jido.AI.Skill.Registry.unregister(spec.name)
:ok = Jido.AI.Skill.Registry.clear()
```

Registry lifecycle guarantees:

- explicit startup via `start_link/1`
- lazy startup via `ensure_started/0` used by public APIs
- safe unregister/clear operations for runtime teardown

## Activation And Session Isolation

Activation state is keyed by `{session_id, skill_name}`. Public activation calls
default to the caller process; pass a stable ID when activation spans processes:

```elixir
{:ok, activation} =
  Jido.AI.Skill.Activation.activate("code-review", session_id: conversation_id)

activation.skill_body
activation.root_dir
activation.resources
```

The `load_skill` action derives its session from `session_id`, then `agent_id`,
then `request_id` in the tool context. ReAct supplies `agent_id`, so separate
agent instances do not share activation state. Its structured result contains:

```elixir
%{
  name: "code-review",
  description: "...",
  instructions: "# Code Review ...",
  root_dir: "/absolute/path/to/code-review",
  resources: %{scripts: [...], references: [...], assets: [...]}
}
```

Skill tool results are marked durable in conversation refs. A ReAct context
replacement with `reason: :compaction` retains the skill output and its matching
assistant tool call.

## Lazy Loading Skill Bodies

Use a compact skill index when full skill bodies would make the agent prompt too
large. The index advertises names and descriptions only; the model can call the
packaged `load_skill` action to retrieve the selected body.

```elixir
index =
  Jido.AI.Skill.Prompt.render_registry_index(
    tags: "support-agent",
    include_allowed_tools: true
  )

# Add `index` to your agent system prompt and expose this action with the agent tools.
Jido.AI.Actions.Skill.LoadSkill
```

The rendered index includes guidance for the model to call `load_skill` with the
skill name. `render_registry_index/1` accepts `:tags` and `:tag_match` so agents
can advertise only the skills intended for that agent.

You can load a skill directly from application code as well:

```elixir
{:ok, loaded} =
  Jido.AI.Actions.Skill.LoadSkill.run(%{name: "code-review"}, %{})

loaded.instructions
loaded.root_dir
loaded.resources
```

`Prompt.render/2` now omits bodies by default. Eager rendering remains available
for deliberate static-prompt use with `include_body: true`; use `render_index/2`
for model-facing catalogs.

## Strict And Lenient Validation

Strict loading (`lenient: false`, the default) enforces the Agent Skills format:

- the declared name exactly matches the parent directory
- descriptions are non-empty and at most 1,024 characters
- compatibility is non-empty and at most 500 characters when present
- metadata contains only string keys and string values

Lenient loading keeps interoperability behavior: it records diagnostics and can
normalize or truncate recoverable values.

## Bounded Discovery And Trust

`Discovery.discover_from/2` defaults to a maximum depth of 6 and 2,000 visited
directories, skips `.git` and `node_modules`, and does not follow directory
symlinks. Custom callers can require trust explicitly:

```elixir
Jido.AI.Skill.Discovery.discover_from(paths,
  trust: &MyApp.Trust.skill_root?/1,
  max_depth: 4,
  max_directories: 500
)
```

An unapproved root returns `{:error, {:untrusted_skill_path, absolute_path}}`;
exceeding the directory bound returns a structured `:discovery_limit_exceeded`
error.

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

- `Jido.AI.Skill.resolve/1` or `Jido.AI.Skill.Registry.lookup/1` returns `NotFound`

Fix:

- ensure skills were registered into the current runtime registry instance
- confirm normalized names (kebab-case) match lookup keys

## Defaults You Should Know

- skill registry stores specs by skill name
- activation registry stores by session ID and skill name
- `body_ref` can be inline or file-backed
- allowed tools are normalized to string names
- `Prompt.render/2` ignores unresolved skills, renders only valid specs, and omits bodies by default

## Demo + Examples

Run the end-to-end demo script:

```bash
mix run examples/scripts/demo/skills_runtime_foundations_demo.exs
```

Prerequisites:

- run from the repository root
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
