# Skills Guide

This guide covers skills in Jido.AI - prompt-based capabilities that extend agent behavior.

## Table of Contents

- [Overview](#overview)
- [Module-Based Skills](#module-based-skills)
- [File-Based Skills](#file-based-skills)
- [Skill API](#skill-api)
- [Prompt Rendering](#prompt-rendering)
- [Built-in Example Skills](#built-in-example-skills)
- [Creating Custom Skills](#creating-custom-skills)

## Overview

`Jido.AI.Skill` provides a unified skill abstraction following the [agentskills.io](https://agentskills.io) specification. Skills inject prompt context into agents, guiding LLM behavior for specific tasks.

**Key concepts:**

| Concept | Description |
|---------|-------------|
| **Skill** | Prompt instructions + tool allowlist for a specific capability |
| **Plugin** | Runtime capability with actions, state, and signal routing (`Jido.Plugin`) |
| **Action** | Executable function that can be exposed as an LLM tool (`Jido.Action`) |

Skills are defined two ways:

1. **Compile-time modules** using `use Jido.AI.Skill`
2. **Runtime-loaded SKILL.md files** with YAML frontmatter

## Module-Based Skills

Define skills as Elixir modules with `use Jido.AI.Skill`:

```elixir
defmodule MyApp.Skills.WeatherAdvisor do
  use Jido.AI.Skill,
    name: "weather-advisor",
    description: "Provides weather-aware travel and activity advice.",
    license: "MIT",
    allowed_tools: ~w(weather_geocode weather_forecast),
    actions: [MyApp.Actions.Weather.Forecast],
    body: """
    # Weather Advisor

    ## Workflow
    1. Determine location
    2. Fetch weather data
    3. Provide contextual advice
    """
end
```

## File-Based Skills

Create a `SKILL.md` file with YAML frontmatter:

```markdown
---
name: code-review
description: Reviews code for quality, security, and best practices.
license: Apache-2.0
allowed-tools: read_file grep git_diff
metadata:
  author: jido-team
  version: "1.0.0"
---

# Code Review

Review code changes and provide feedback...
```

Load at runtime:

```elixir
{:ok, spec} = Jido.AI.Skill.Loader.load("priv/skills/code-review/SKILL.md")
Jido.AI.Skill.Registry.register(spec)
```

## Skill API

Both module and file-based skills support the same interface:

```elixir
# Get the skill specification
Jido.AI.Skill.manifest(skill)

# Get the skill body text
Jido.AI.Skill.body(skill)

# Get allowed tools
Jido.AI.Skill.allowed_tools(skill)

# Get associated actions
Jido.AI.Skill.actions(skill)

# Resolve a skill (module, spec, or name string)
Jido.AI.Skill.resolve("weather-advisor")
```

### Frontmatter Fields

| Field | Required | Description |
|-------|----------|-------------|
| `name` | Yes | 1-64 chars, lowercase kebab-case (`^[a-z0-9]+(-[a-z0-9]+)*$`) |
| `description` | Yes | 1-1024 chars |
| `license` | No | License identifier (e.g., "MIT", "Apache-2.0") |
| `compatibility` | No | Version requirements (max 500 chars) |
| `metadata` | No | Arbitrary metadata map |
| `allowed-tools` | No | Space-delimited or list of tool names |
| `tags` | No | List of categorization tags |

## Prompt Rendering

Use `Jido.AI.Skill.Prompt` to render skills into system prompts:

```elixir
alias Jido.AI.Skill.Prompt

# Render multiple skills
skills = [MyApp.Skills.Calculator, "code-review"]
prompt_text = Prompt.render(skills)

# Render a single skill
Prompt.render_one(MyApp.Skills.Calculator)

# Collect allowed tools from skills
Prompt.collect_allowed_tools(skills)
# => ["add", "subtract", "read_file", "grep"]

# Filter tools by skill allowlists
Prompt.filter_tools(all_tools, skills)
```

### Rendered Output Example

```markdown
You have access to the following skills:

## calculator
Performs precise arithmetic calculations using tool calls.
Allowed tools: add, subtract, multiply, divide

# Calculator Skill

## Purpose
Use this skill when users need help with arithmetic...

## code-review
Reviews code for quality and best practices.
Allowed tools: read_file, grep, git_diff

# Code Review

Review code changes and provide feedback...
```

## Built-in Example Skills

| Skill | Module | Purpose |
|-------|--------|---------|
| **Calculator** | `Jido.AI.Examples.Skills.Calculator` | Arithmetic operations |
| **Skill Writer** | `Jido.AI.Examples.Skills.SkillWriter` | Creates new skill definitions |

### Calculator Skill

```elixir
Jido.AI.Examples.Skills.Calculator
# Allowed tools: add, subtract, multiply, divide
# Actions: Jido.Tools.Arithmetic.*
```

### Skill Writer Skill

A meta-skill for creating new skills:

```elixir
Jido.AI.Examples.Skills.SkillWriter
# Allowed tools: validate_skill_name, write_module_skill, write_file_skill
```

## Skills vs Plugins

Skills and Plugins serve different purposes:

| Aspect | Skill (`Jido.AI.Skill`) | Plugin (`Jido.Plugin`) |
|--------|-------------------------|------------------------|
| **Purpose** | Prompt instructions for LLM | Runtime agent capabilities |
| **Execution** | Injected into system prompt | Executes actions, routes signals |
| **State** | Stateless (prompt text only) | Has state, lifecycle callbacks |
| **Definition** | Module or SKILL.md file | Elixir module only |
| **Use case** | Guide LLM behavior | Add capabilities to agents |

## Creating Custom Skills

### Module-Based Skill

```elixir
defmodule MyApp.Skills.DocumentSummarizer do
  use Jido.AI.Skill,
    name: "document-summarizer",
    description: "Summarizes long documents into key points and actionable insights.",
    license: "MIT",
    allowed_tools: ~w(extract_text chunk_text summarize),
    actions: [
      MyApp.Actions.ExtractText,
      MyApp.Actions.ChunkText,
      MyApp.Actions.Summarize
    ],
    tags: ["nlp", "summarization", "documents"],
    body: """
    # Document Summarizer

    ## Purpose
    Use when users need to condense long documents into key points.

    ## Workflow
    1. Extract text from the document
    2. Chunk into manageable sections
    3. Summarize each chunk
    4. Combine into final summary

    ## Best Practices
    - Preserve key facts and figures
    - Maintain logical flow
    - Highlight actionable items
    """
end
```

### File-Based Skill

Create `priv/skills/my-skill/SKILL.md`:

```markdown
---
name: my-skill
description: Description of what the skill does.
license: Apache-2.0
allowed-tools: tool1 tool2 tool3
tags:
  - category1
  - category2
metadata:
  author: your-name
  version: "1.0"
---

# My Skill

## Purpose
When to use this skill...

## Workflow
1. Step one
2. Step two
3. Step three

## Examples
Show concrete examples...
```

Load at runtime:

```elixir
# In application startup
Jido.AI.Skill.Registry.start_link()
Jido.AI.Skill.Registry.load_from_paths(["priv/skills"])
```

## Skill Best Practices

1. **Clear purpose**: Define when the skill should be activated
2. **Workflow documentation**: Step-by-step instructions for the LLM
3. **Concrete examples**: Show input/output examples
4. **Tool alignment**: `allowed_tools` should match available actions
5. **Descriptive names**: Use lowercase kebab-case (e.g., `code-review`)

## Running the Demo

```bash
mix run scripts/skills_demo.exs
```

This demonstrates:
- Loading module and file-based skills
- Skill introspection and prompt rendering
- Agent interaction with multiple skills

## Next Steps

- [Plugins Guide](./05_plugins.md) - Runtime agent capabilities
- [Tool System Guide](./06_tool_system.md) - Action execution
- [Strategies Guide](./02_strategies.md) - ReAct and other strategies
