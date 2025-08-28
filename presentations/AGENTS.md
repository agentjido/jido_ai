# AGENTS.md - Presentations Development Guide

## Slidev Development Workflow

### Common Commands

From the `presentations/` directory:

**Development:**
- `npm run dev` - Start development server for intro slides (default)
- `npm run dev:intro` - Start development server for intro slides specifically
- Opens at <http://localhost:3030>

**Building:**
- `npm run build` - Build intro slides for production
- `npm run build:intro` - Build intro slides specifically
- `npm run build:all` - Build all slide decks

**Export:**
- `npm run export` - Export intro slides to PDF/PNG
- `npm run export:intro` - Export intro slides specifically

**Deck Management:**
- `npm run deck:new` - Create new slide deck from template

### Slidev Syntax Rules & Guidelines

#### Frontmatter Requirements

**CRITICAL:** Each slide's frontmatter MUST be enclosed with `---` on both sides:

```markdown
---
layout: center
class: text-center
---

# Slide Content Here
```

**Common mistake that breaks syntax highlighting:**
```markdown
---
layout: center

# This will cause styling issues!
```

#### Code Block Best Practices

1. **Always specify language** for proper syntax highlighting:
```markdown
```elixir
defmodule MyModule do
  # code here
end
``` (close with triple backticks)
```

2. **Avoid nested code blocks** in bullet points - use separate sections instead

3. **For inline code**, use single backticks: `mix deps.get`

#### Layout Options

- `layout: default` - Standard slide layout
- `layout: center` - Centered content (good for transitions)
- `layout: cover` - Title slides only
- `layout: two-cols` - Two column layout

#### Theme Configuration

- Use `theme: default` for reliable syntax highlighting
- Custom themes in `themes/` directory can be referenced as `theme: slidev-theme-agent-jido`
- Test with default theme first if styling issues occur

#### Mermaid Diagrams

Always use proper mermaid code blocks:
```markdown
```mermaid
flowchart LR
    A[Start] --> B[End]
``` (close with triple backticks)
```

#### Speaker Notes

Use HTML comments for speaker notes:
```markdown
<!--
Notes:
- Remember to mention this point
- Timing: 2 minutes on this slide
-->
```

### Project Structure

```
presentations/
├── package.json              # Build scripts and dependencies
├── slidev/                   # Slide decks
│   ├── 01-intro/            # Introduction presentation
│   │   └── slides.md        # Main slides file
│   └── 02-advanced/         # Future advanced topics
├── themes/                   # Custom Slidev themes
│   └── slidev-theme-agent-jido/
├── scripts/                  # Build automation
└── AGENTS.md                # This file
```

### Troubleshooting

**Syntax highlighting issues:**
1. Check frontmatter is properly enclosed with `---`
2. Verify code block language is specified
3. Try `theme: default` if custom theme causes problems

**Development server not updating:**
1. Restart with `npm run dev`
2. Check for syntax errors in slides.md
3. Clear browser cache

### Dependencies

- `@slidev/cli` - Core Slidev functionality
- `vue` - Vue.js for interactive components
- `lz-string` - String compression utilities
- `slidev-theme-agent-jido` - Custom Jido theme

### Best Practices

1. **Start with default theme** for new presentations
2. **Test code blocks** in isolation if styling issues occur
3. **Keep slides simple** - one concept per slide
4. **Use speaker notes** for timing and delivery reminders
5. **Preview in browser** before presenting (localhost:3030)
6. **Have PDF backup** exported via `npm run export`
