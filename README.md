# AshJido

> **⚠️ PREVIEW - NOT READY FOR PRODUCTION USE**  
> This library is in active development and not yet stable. APIs may change without notice.

Bridge Ash Framework resources with Jido agents. Automatically converts Ash actions into Jido tools, making every Ash action available in an agent's toolbox.

## Quick Start

```elixir
defmodule MyApp.User do
  use Ash.Resource,
    extensions: [AshJido]

  actions do
    create :register
    read :by_id
    update :profile
  end

  jido do
    action :register, name: "create_user"
    action :by_id, name: "get_user" 
    action :profile, tags: ["user-management"]
  end
end
```

Generates Jido.Action modules that agents can use:

```elixir
# In your agent
MyApp.User.Jido.Register.run(
  %{name: "John", email: "john@example.com"}, 
  %{domain: MyApp.Domain}
)
```

## Key Features

- **Automatic Tool Generation**: Every Ash action becomes a Jido tool
- **Type Safety**: Ash types map to NimbleOptions schemas  
- **Policy Integration**: Respects Ash authorization policies
- **Smart Defaults**: Intelligent naming and categorization
- **Bulk Exposure**: `all_actions` for rapid setup
- **AI-Optimized**: Tags and descriptions for better agent discovery

## DSL Options

```elixir
jido do
  # Simple exposure
  action :create
  
  # Custom configuration  
  action :update, 
    name: "modify_user",
    description: "Update user information",
    tags: ["user-management", "data-modification"]
    
  # Bulk exposure
  all_actions except: [:internal_action]
end
```

## Installation

```elixir
def deps do
  [
    {:ash_jido, "~> 0.1.0"}
  ]
end
```

## Context Requirements

Actions require a context with at minimum a domain:

```elixir
context = %{
  domain: MyApp.Domain,
  actor: current_user,     # optional: for authorization
  tenant: "org_123"        # optional: for multi-tenancy
}

MyApp.User.Jido.Create.run(params, context)
```

## Documentation

- [Usage Rules](usage-rules.md) - Comprehensive patterns and best practices
- [API Documentation](https://hexdocs.pm/ash_jido) - Auto-generated docs

## Development

```bash
mix deps.get
mix test
mix format
```

## License

MIT
