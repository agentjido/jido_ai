# SKILL.md Instructions

`Jido.AI.Skill` lets a tool-capable Agent load trusted instructions from
`SKILL.md` files. It uses the normal dynamic tool source boundary. It does not
add an Agent Plugin or keep activation state.

## Create a skill

A skill root contains one directory for each skill:

```text
.agents/skills/
└── code-review/
    └── SKILL.md
```

The file starts with YAML front matter. The `name` must match the directory
name.

```markdown
---
name: code-review
description: Review code for bugs, regressions, and missing tests.
---

Review the changed code before you suggest edits.

Report concrete findings first. Include the file and line for each finding.
```

Names can contain lowercase letters, digits, and single hyphens. A name can
have at most 64 bytes. A description can have at most 1,024 bytes.

## Add skills to a request

Build a source from one or more trusted roots. Pass it in the execution
context:

```elixir
skill_source = Jido.AI.Skill.source([".agents/skills"])

MyApp.SupportAgent.cmd(agent, request,
  context: %{jido_ai_tool_sources: [skill_source]}
)
```

`Jido.AI.Skill.source/1` expands each root to an absolute path. The source
configuration is portable data. Request input cannot add or change the roots.

At request start, Jido AI scans only the direct child directories of each
root. It reads the front matter and adds one dynamic tool named `load_skill`.
The tool description contains the sorted skill catalog.

When the model calls `load_skill`, Jido AI resolves the exact discovered name
and returns the Markdown body. The normal tool result path adds the body to the
conversation. The normal `tool_output_bytes` limit applies to this result.

## Inspect skills

You can inspect or load skills without an Agent request:

```elixir
{:ok, skills} = Jido.AI.Skill.discover([".agents/skills"])

{:ok, skill} =
  Jido.AI.Skill.load([".agents/skills"], "code-review")

skill.instructions
```

Discovery fails if a configured root is missing, a discovered file is
invalid, or two roots contain the same skill name. Directories without an
exact `SKILL.md` file are ignored.

## Tool policy

`load_skill` is a normal dynamic tool. A request tool policy can hide it or
require review. If a policy has an explicit `visible` list, that list must
contain `load_skill` before the model can use skills.

Automatic selection works only in reasoning flows that expose tools. A host
can call `Jido.AI.Skill.load/2` when it needs to add skill instructions by
another method.

## Scripts and other files

Jido AI supports only `SKILL.md` instructions. It does not inspect or execute
files in `scripts/`, `references/`, `assets/`, or other skill directories.

An application that needs another capability can provide a separate trusted
`Jido.AI.ToolSource`. Jido AI does not give scripts an execution permission or
a special script interface.
