# Jido Presentations

This folder contains all Slidev presentations for the Jido project.

## Structure

Each presentation should be in its own subdirectory:

```
presentations/
├── default/           # Default/template presentation
├── architecture/      # System architecture presentation
├── getting-started/   # Getting started guide
└── ...               # Other presentations
```

## Creating a New Presentation

Use the helper script to create a new presentation:

```bash
bun run new presentation-name
```

This will:
1. Create a new directory under `presentations/`
2. Copy the default template
3. Set up the basic structure

## Development

### Start development server for a specific presentation:
```bash
bun run dev:default          # Default presentation
bun run dev:presentation-name # Named presentation
```

### Build a presentation:
```bash
bun run build:default          # Default presentation
bun run build:presentation-name # Named presentation
```

### Export as PDF:
```bash
bun run export:default          # Default presentation
bun run export:presentation-name # Named presentation
```

## Adding New Presentations

After creating a new presentation with `bun run new`, you'll need to add the corresponding scripts to `package.json`:

```json
{
  "scripts": {
    "dev:your-presentation": "slidev presentations/your-presentation --open",
    "build:your-presentation": "slidev build presentations/your-presentation",
    "export:your-presentation": "slidev export presentations/your-presentation"
  }
}
```
