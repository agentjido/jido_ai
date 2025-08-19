# Signal Router

High-performance trie-based signal routing with pattern matching and priority execution.

## Route Patterns

### Exact Matches
```elixir
{"user.created", HandleUserCreated}
{"payment.processed", ProcessPayment}
```

### Single Wildcards (`*`)
Matches exactly one segment:
```elixir
{"user.*.updated", HandleUpdate}  # matches "user.profile.updated", not "user.profile.settings.updated"
{"*.error", HandleError}          # matches "auth.error", "db.error"
```

### Multi-level Wildcards (`**`)
Matches zero or more segments:
```elixir
{"audit.**", AuditLogger}         # matches "audit", "audit.user", "audit.user.login"
{"metrics.**", MetricsCollector}  # matches all metrics signals
```

### Pattern Rules
- Segments: `[a-zA-Z0-9._*-]+`
- No consecutive dots (`..`)
- No consecutive multi-wildcards (`**...**`)

## Trie-Based Matching

The router organizes handlers in a prefix tree for O(log n) lookup performance:

```elixir
# Routes stored as trie nodes
user
├── created (handler: HandleUserCreated)
├── * (handler: HandleUserWildcard)
└── profile
    └── updated (handler: HandleProfileUpdate)
```

Matching algorithm:
1. Exact segment match
2. Single wildcard (`*`) match  
3. Multi-level wildcard (`**`) match

## Route Priorities

Handlers execute by priority order (-100 to 100):

```elixir
# High priority audit logging
{"audit.**", AuditLogger, 100}

# Default priority business logic  
{"user.created", HandleUserCreated, 0}

# Low priority metrics
{"**", MetricsCollector, -75}
```

### Complexity Scoring

Priority calculation:
1. Base score: `segment_count * 2000`
2. Exact match bonus: `3000 * (segment_count - position)`
3. Wildcard penalties:
   - Single (`*`): `1000 - position * 100`
   - Multi (`**`): `2000 - position * 200`

More specific paths execute before wildcards.

## Dynamic Routing

### Adding Routes
```elixir
{:ok, router} = Router.add(router, [
  {"metrics.**.latency", LatencyTracker, 50},
  {"system.error", ErrorHandler}
])
```

### Removing Routes
```elixir
{:ok, router} = Router.remove(router, ["metrics.**", "old.route"])
```

### Pattern Matching Functions
```elixir
large_payment_filter = fn signal -> 
  signal.data.amount > 1000 
end

{:ok, router} = Router.add(router, [
  {"payment.processed", large_payment_filter, AlertLargePayment, 75}
])
```

### Multiple Dispatch
```elixir
{"system.error", [
  {MetricsAdapter, [type: :error]},
  {AlertAdapter, [priority: :high]},
  {LogAdapter, [level: :error]}
]}
```

## Signal Routing

```elixir
{:ok, targets} = Router.route(router, %Signal{
  type: "user.profile.updated",
  data: %{user_id: "123"}
})
# Returns: [HandleUserWildcard, HandleProfileUpdate] (priority order)
```

Pattern matching validation:
```elixir
Router.matches?("user.created", "user.*")     # true
Router.matches?("audit.user.login", "audit.**")  # true  
Router.matches?("user.profile.updated", "user.*")  # false
```
