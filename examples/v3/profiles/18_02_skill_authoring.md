# 18_02: Automatic skill authoring

[Agents](../lib/examples/18_skills/18_02_skill_authoring/agent.ex) and
[21 integration cases](../test/examples/18_skills/18_02_skill_authoring_test.exs)
use the real loading Actions, the existing Session/Flow path, and the shared
HTTP mock. The public Agent option, native DSL, source data, Builder, and JSON
produce the same runtime behavior.

## Declare the source

The public Agent accepts `agent_skills`. For example:

```elixir
use Jido.AI.Agent,
  name: "reviewer",
  model: :fast,
  tools: [],
  agent_skills: [modules: [MyApp.Skills.Review]]
```

Inside a native `ai` profile, use:

```elixir
skills do
  skill MyApp.Skills.Review
  load_path "priv/skills"
  max_depth 4
  max_directories 500
  resource_policy max_text_bytes: 64_000
  resource_provider {MyApp.SkillResources, :handle}
end
```

The profile must use ReAct and `requests mode: :session`. The complete native
Agent is in the linked example. A source map uses `skills: %{modules: [...],
paths: [...], trust: true}`. A JSON source uses the existing host Registry for
trusted module, callback and static value references. JSON does not import code.

`nil`, `false`, and `[]` disable automatic skills. `true` selects the standard
trusted roots. A list of paths trusts those roots. A keyword list or source map
requires explicit trust for file discovery. Repeated `load_path` declarations
imply trust unless the block sets it. Do not combine `paths` and `load_path`.
A source with `paths: []` stays enabled with a closed empty catalogue. Module
or runtime Spec sources default to no filesystem scan.

Static declarations accept boolean trust or an exported `{Module, function,
args}` callback. The callback receives the path before its extra arguments.
Runtime provider callbacks use the existing MFA contract. Stored definitions
cannot contain closures. The manual `AgentIntegration.prepare/1` API retains
its runtime callback forms.

## Prepare once per live owner

Compilation validates source references without calling `manifest/0` or reading
skill files. Static `new` and Builder/Codec work do not read the build directory.
The existing Session child prepares each profile's catalogue when the live
Agent starts. Relative paths use that runtime directory. Discovery errors and
bounds failures stop startup before any model request.

Runtime Specs take precedence over module Specs, then discovered files. Shadowed
entries produce diagnostics. The selected set supplies both the prompt index
and the loader's scoped lookup map. Discovery keeps metadata; activation reads
and strictly checks the current file body. Native module metadata is retained.

A nonempty catalogue adds the loading Actions and the selected module Actions.
Explicit tool declarations with the same public name win. Existing request tool
selection still applies after these defaults. Skill metadata does not install
Plugins: declare those Plugins in the Agent definition. The automatic tools
keep the public Agent's timeout and retry defaults.

The source binding controls the catalogue, provider and resource policy. It
replaces conflicting reserved fields in host context. Request `tool_context`
cannot set those reserved fields. The manual binding path in [18_01](18_01_skill_runtime.md)
remains available for profiles without automatic skills.

## Inspect, change and restore

`Jido.AI.Session.skill_catalog(server, profile_id)` returns the selected Specs,
index and diagnostics. Omit `profile_id` for the default profile. It does not
return provider handles. Pure configuration getters show declared values and
portable overrides; they do not run discovery or append the transient index.

Live tool registration starts from the effective catalogue. Removing a loading
tool removes that entry from the next request. Use live server helpers to change
automatic tools; pure Agent helpers cannot inspect the runtime catalogue.
An explicit prompt replacement wins over the generated index. It does not
remove the tool catalogue.

Each profile has a separate catalogue and activation scope. Restore rebuilds
the catalogue from current runtime sources while preserving saved instructions.
It sends no model request by itself. Old provider handles and activation state
are not serialized. The existing activation and resource bounds in 18_01 apply.
Pure Session admission with automatic skills returns an error because it has no
live owner for discovery and activation.

## Remaining package work

These cases do not close standalone skill continuation, installed resource and
CLI checks, complete Agent state conversion, or root package and consumer
validation. Root dependency files still use v2. All history rows remain pending
until their complete acceptance requirements pass.
