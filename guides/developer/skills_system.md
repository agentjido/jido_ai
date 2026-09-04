# Skills System

You need to package reusable instructions/capabilities and load them safely.

After this guide, you can attach trusted Agent Skills with progressive disclosure,
use session-scoped activation, validate skill files, and bound custom discovery.

## Core Contracts

- `Jido.AI.Skill`
- `Jido.AI.Skill.Spec`
- `Jido.AI.Skill.Loader`
- `Jido.AI.Skill.Registry`
- `Jido.AI.Skill.Resources`
- `Jido.AI.Skill.ResourcePolicy`
- `Jido.AI.Skill.AgentIntegration`
- `Jido.AI.Skill.Prompt`
- `Jido.AI.Actions.Skill.LoadSkill`
- `Jido.AI.Actions.Skill.LoadResource`
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
`Jido.AI.Actions.Skill.LoadSkill` and `Jido.AI.Actions.Skill.LoadResource` to the
tool list, and makes metadata-only specs
available through reserved tool context for that agent. Discovery and catalog
construction happen when each agent instance initializes. The selected skill
file is read and strictly validated when `load_skill` activates it. Thus, the
catalog does not keep all skill bodies in memory.

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
  exclude_directories: [".git", "node_modules", "deps", "_build"],
  resource_policy: [
    max_resources: 128,
    max_depth: 6,
    max_directories: 512,
    max_listing_bytes: 32_768,
    max_file_bytes: 524_288,
    max_text_bytes: 131_072,
    binary: :reject
  ]
]
```

Keyword options must include an explicit `trust` policy. Omitting it rejects
every discovered root; passing a path list directly is the shorthand for
trusting exactly those roots.

Hosts can also supply runtime specs directly. Runtime specs must include a valid
name, description, `source: nil`, and inline body. They are not discovered from
the filesystem and cannot retain a filesystem root:

```elixir
runtime_specs = [
  %Jido.AI.Skill.Spec{
    name: "billing-playbook",
    description: "Answer billing questions using current tenant policy.",
    source: nil,
    body_ref: {:inline, "# Billing Playbook\n\nCheck tenant policy before answering."},
    metadata: %{"owner" => "support"},
    tags: ["support"]
  }
]

provider = fn
  %{operation: :list}, %{tenant_id: tenant_id} ->
    {:ok,
     %{
       resources: [
         %{
           id: "tenant-policy:#{tenant_id}",
           name: "#{tenant_id}-policy.md",
           type: :reference,
           size: 512
         }
       ],
       complete: true
     }}

  %{operation: :load, resource_id: id}, %{tenant_id: tenant_id} ->
    content = MyApp.PolicyStore.fetch!(tenant_id, id)
    {:ok, %{resource_id: id, content: content, size: byte_size(content)}}
end

use Jido.AI.Agent,
  name: "support_agent",
  agent_skills: [
    specs: runtime_specs,
    resource_provider: provider,
    resource_policy: [max_text_bytes: 131_072]
  ]
```

Runtime specs can be mixed with discovered paths. Runtime specs win over
discovered skills with the same name, and shadowed discovered entries are
reported in diagnostics. Duplicate runtime names are rejected. Filesystem-backed
skills must enter through trusted discovery (`paths` plus `trust`) rather than
through `specs:`.

The provider is called with one of these requests:

```elixir
%{operation: :list, skill: spec, policy: policy}
%{operation: :load, skill: spec, resource_id: opaque_id, policy: policy}
```

It must return one of these shapes:

```elixir
{:ok, %{resources: resource_entries, complete: boolean()}}
{:ok, %{resource_id: opaque_id, content: text, size: non_neg_integer()}}
{:error, reason}
```

Provider entries require `id`, `name`, and `size`. Optional fields are `type`,
`modified`, `mime_type`, and `metadata`. The `id` is opaque: Jido preserves it
byte-for-byte and never parses, normalizes, joins, sorts, or interprets it. The
`name` is descriptive only and is not used for loading.

Provider listings are ordered. Policy enforcement truncates at the first entry
that violates count, declared-size, or encoded-listing limits; that entry and all
later entries are excluded. Entries that cannot be encoded for listing, including
malformed metadata, reject the provider listing with a structured error.

Jido validates and normalizes provider output instead of trusting it. Reserved
Agent Skills context is removed before the callback runs; host context such as
tenant IDs remains available. Provider-backed resource IDs are authorized only
when they appeared in the activated skill's post-policy listing. Unlisted IDs are
forbidden even when the provider reported `complete: false`; clear and reactivate
the skill to refresh the authorized listing.

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
default to the caller process. Name activation checks the registry and does not
scan the filesystem by default. Pass a stable ID when activation spans
processes:

```elixir
{:ok, activation} =
  Jido.AI.Skill.Activation.activate("code-review", session_id: conversation_id)

activation.skill_body
activation.root_dir
activation.resources

# Release activation state when the session ends.
:ok = Jido.AI.Skill.Activation.clear(session_id: conversation_id)
```

To activate by name from a filesystem root, give the paths and the trust policy
in the same call:

```elixir
{:ok, activation} =
  Jido.AI.Skill.Activation.activate("code-review",
    paths: ["priv/skills"],
    trust: true,
    session_id: conversation_id
  )
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
  resources: %{resources: [...], scripts: [...], references: [...], assets: [...]}
}
```

The `resources` value also has the complete selector list, limit details, and
truncation state. Filesystem skills use `relative_path`; provider-backed runtime
skills use opaque `id` values:

```elixir
%{
  resources: [%{relative_path: "LICENSE", size: 1_067, ...}],
  scripts: [...],
  references: [...],
  assets: [...],
  complete: true,
  truncated: false,
  truncation_reasons: [],
  limits: %{...}
}
```

```elixir
%{
  resources: [%{id: "tenant-policy:acme", name: "policy.md", size: 1_067, ...}],
  scripts: [...],
  references: [...],
  assets: [...],
  complete: true,
  truncated: false,
  truncation_reasons: [],
  limits: %{...}
}
```

The `resources` field is the complete aggregate listing. The conventional
`references`, `assets`, and `scripts` groups are filtered views of that same
manifest. Entries intentionally appear in both the aggregate list and their
typed list; do not deduplicate across these fields because they serve different
views. The general filesystem list also includes root files and custom
directories. It excludes the root `SKILL.md` and does not contain absolute
paths.

Skill tool results are marked durable in conversation refs. A ReAct context
replacement with `reason: :compaction` retains the skill output and its matching
assistant tool call.

## Bounded Resource Loading

After `load_skill` activates a filesystem skill, use `load_skill_resource` with
one listed relative path:

```elixir
{:ok, resource} =
  Jido.AI.Actions.Skill.LoadResource.run(
    %{name: "code-review", relative_path: "references/checks.md"},
    %{agent_id: conversation_id}
  )

resource.content
```

For provider-backed runtime skills, use the listed opaque `resource_id` instead:

```elixir
{:ok, resource} =
  Jido.AI.Actions.Skill.LoadResource.run(
    %{
      name: "about-jaicool",
      resource_id: "b7754895-90f8-4594-b6be-c80fd0859545"
    },
    %{agent_id: conversation_id, tenant_id: "acme"}
  )
```

The same provider-backed tool arguments as JSON are:

```json
{
  "name": "about-jaicool",
  "resource_id": "b7754895-90f8-4594-b6be-c80fd0859545"
}
```

The action requires activation in the same runtime session. Filesystem resources
use the bundled file loader. Runtime specs configured with `resource_provider:`
use their opaque provider IDs and call the provider for every load, so resource
content is never cached by Jido.

Filesystem resources reject absolute paths, traversal, the root `SKILL.md`,
symlinks, hard-link aliases of `SKILL.md`, oversized files, oversized text, and
binary or non-UTF-8 content. Provider-backed resources validate only the opaque
ID type, emptiness, length, listing authorization, response identity, declared
size, loaded text size, and binary/non-UTF-8 content. Missing, invalid,
oversized, binary, provider-failed, and malformed resources return structured
action errors.

`Jido.AI.Skill.ResourcePolicy` has these defaults:

- 256 resources
- depth 8
- 1,024 visited directories
- 64 KiB for the encoded general-resource list
- 1 MiB for one file
- 256 KiB of returned text
- binary text loading rejected

When a filesystem listing reaches a count, depth, directory, or payload limit,
`complete` is false and `truncation_reasons` identifies the reached limits. When
a provider listing reaches a count, declared-size, or encoded payload limit,
`complete` is false and `truncation_reasons` identifies the reached limits.
Provider listings marked incomplete add `:provider_incomplete`.

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

- the file is named exactly `SKILL.md`
- the declared name exactly matches the parent directory
- descriptions are non-empty and at most 1,024 characters
- license is a string when present
- compatibility is non-empty and at most 500 characters when present
- metadata contains only string keys and string values
- `allowed-tools` is a space-separated string when present
- only specification fields are present at the top level

Put Jido-specific file metadata under namespaced metadata keys:

```yaml
metadata:
  jido_ai.tags: "support review"
  jido_ai.version: "1.0.0"
```

Module-based Jido skills can continue to use native `tags`, `vsn`, `actions`,
and `plugins` options.

Lenient loading keeps interoperability behavior: it records diagnostics and can
normalize or truncate recoverable values.

The experimental Agent Skills `allowed-tools` field is advisory in Jido.AI.
Automatic activation does not approve, enable, or restrict tools from this
field. A host can apply an explicit policy with
`Jido.AI.Skill.Prompt.filter_tools/2`, but that restrictive use is a host choice
and is not the Agent Skills pre-approval meaning.

## Bounded Discovery And Trust

`Discovery.discover_from/2` defaults to a maximum depth of 6 and 2,000 visited
directories, skips `.git` and `node_modules`, and does not follow file or
directory symlinks. It reads at most 64 KiB of frontmatter and does not read the
skill body. Custom callers can require trust explicitly:

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

Root order is significant. The first root wins when two roots contain the same
skill name. `discover_from_with_diagnostics/2` returns a `:shadowed_skill`
warning that names the selected and shadowed files. Agent integration also
returns these diagnostics.

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
- validation prints collected warnings and errors
- `--strict` raises when any skill has a warning or error (non-zero exit)

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
- filesystem resource listings use relative paths, provider listings use opaque IDs, and both report incomplete results
- resource text loading rejects binary content
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
