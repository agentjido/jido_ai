# AshJido Usage Rules

## Core Integration Patterns

### Resource Extension Setup
- Always use `extensions: [AshJido]` in your Ash resource definition
- Define the `jido` section after your `actions` section for clarity
- Use the DSL to selectively expose actions as Jido tools

### Action Exposure Strategies

#### Individual Action Configuration
```elixir
jido do
  action :create
  action :read, name: "list_users", description: "List all users"
  action :update, tags: ["user-management", "data-modification"]
end
```

#### Bulk Action Exposure
```elixir
jido do
  all_actions
  # or with filtering
  all_actions except: [:internal_action, :admin_only]
  all_actions only: [:create, :read, :update]
end
```

## Naming Conventions

### Default Naming Pattern
- Auto-generated names follow: `{resource}_{action}` format
- Examples: `user_create`, `post_update`, `comment_delete`

### Custom Naming
- Use `name:` option for custom action names
- Use `module_name:` for custom module naming
- Keep names descriptive and AI-friendly

### Module Generation
- Default modules: `MyApp.User.Jido.Create`
- Custom modules: specify with `module_name:` option

## Context Requirements

### Domain Configuration
- Always provide `domain:` in action context
- Use `%{domain: MyApp.Domain}` pattern
- Auto-discovery available but explicit is preferred

### Actor and Tenant
- Include `actor:` for authorization
- Include `tenant:` for multi-tenancy
- Example: `%{domain: MyDomain, actor: current_user, tenant: "org_123"}`

## Action Type Mappings

### CRUD Operations
- `:create` actions → `data_creation` category
- `:read` actions → `data_retrieval` category  
- `:update` actions → `data_modification` category
- `:destroy` actions → `data_deletion` category

### Custom Actions
- `:action` type → `custom_operation` category
- Use descriptive names for better AI discovery
- Add relevant tags for categorization

## Parameter Handling

### Input Processing
- String keys auto-converted to atoms when appropriate
- Use standard Ash argument patterns
- Include validation through NimbleOptions schemas

### Output Formatting
- Default: `output_map?: true` converts structs to maps
- Set `output_map?: false` to preserve Ash structs
- Read actions return `%{results: [...], count: N}` format
- Single operations return `%{result: data}` format

## Error Handling

### Ash Error Conversion
- Ash errors automatically wrapped as Jido.Error
- Field-level validation errors preserved
- Authorization errors mapped to appropriate Jido types

### Error Categories
- `Ash.Error.Forbidden` → `:authorization_error`
- `Ash.Error.Invalid` → `:validation_error`
- `Ash.Error.Framework` → `:system_error`
- `Ash.Error.Unknown` → `:execution_error`

## Best Practices

### Security
- Always use Ash policies for authorization
- Don't expose sensitive actions without proper filtering
- Use `except:` to exclude admin or internal actions

### Performance
- Use pagination parameters for read actions
- Consider `limit:` and `offset:` for large datasets
- Enable pagination with `pagination?: true` (default)

### AI Integration
- Add descriptive tags for better AI discovery
- Use clear, descriptive action names
- Include comprehensive descriptions
- Tag actions by domain: `["user-management", "content", "analytics"]`

### Documentation
- Leverage auto-generated module documentation
- Actions inherit descriptions from Ash definitions
- Custom descriptions override defaults

## Common Patterns

### User Management Resource
```elixir
jido do
  action :create, name: "register_user"
  action :read, name: "list_users", tags: ["user-management", "public"]
  action :update, name: "update_profile"
  action :destroy, name: "delete_account", tags: ["user-management", "destructive"]
end
```

### Content Resource
```elixir
jido do
  all_actions except: [:internal_update]
  # Auto-generates: create_post, list_posts, update_post, delete_post
end
```

### Custom Business Logic
```elixir
jido do
  action :activate, name: "activate_user", tags: ["user-management", "state-change"]
  action :calculate_metrics, tags: ["analytics", "reporting"]
end
```

## Troubleshooting

### Domain Not Found Error
- Ensure resource is registered in a domain
- Provide explicit domain in context
- Check domain module includes the resource

### Action Not Found Error
- Verify action exists in resource definition
- Check spelling and exact action name
- Ensure action is public (not private)

### Type Conversion Issues
- Check Ash type → NimbleOptions mapping
- Verify custom types are properly handled
- Use string keys for JSON/API inputs

### Module Compilation Issues
- Ensure Jido dependency is available
- Check for circular dependencies
- Verify proper extension loading order
