# ExDbug

[![Hex.pm](https://img.shields.io/hexpm/v/ex_dbug.svg)](https://hex.pm/packages/ex_dbug)
[![Docs](https://img.shields.io/badge/hex-docs-blue.svg)](https://hexdocs.pm/ex_dbug)

Debug utility for Elixir applications, inspired by the Node.js 'debug' package. 
Provides namespace-based filtering, rich metadata support, and compile-time optimization.

## Features

* 🔍 Namespace-based debug output filtering
* 📊 Rich metadata support with customizable formatting
* ⚡ Zero runtime cost when disabled (compile-time optimization)
* 🌍 Environment variable-based filtering
* 📝 Automatic metadata truncation for large values
* 🔧 Configurable debug levels and context-based filtering
* 📈 Value tracking through pipelines
* ⏱️ Optional timing and stack trace information

## Installation

Add `ex_dbug` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:ex_dbug, "~> 1.0"}
  ]
end
```

## Basic Usage

Add `use ExDbug` to your module and use the `dbug/1,2,3` or `error/1,2,3` macros:

```elixir
defmodule MyApp.Worker do
  use ExDbug, context: :worker

  def process(data) do
    dbug("Processing data", size: byte_size(data))
    # ... processing logic
    dbug("Completed processing", status: :ok)
  end
end
```

## Configuration

### Compile-Time Configuration

In your `config.exs`:

```elixir
config :ex_dbug,
  enabled: true,  # Set to false to compile out all debug calls
  config: [      # Default options for all ExDbug uses
    max_length: 500,
    truncate_threshold: 100,
    include_timing: true,
    include_stack: true,
    max_depth: 3,
    levels: [:debug, :error]
  ]
```

### Runtime Configuration

Set the `DEBUG` environment variable to control which namespaces are logged:

```bash
# Enable all debug output
DEBUG="*" mix run

# Enable specific namespace
DEBUG="myapp:worker" mix run

# Enable multiple patterns
DEBUG="myapp:*,other:thing" mix run

# Enable all except specific namespace
DEBUG="*,-myapp:secret" mix run
```

## Advanced Usage

### Metadata Support

All debug macros accept metadata as keyword lists:

```elixir
dbug("User login", 
  user_id: 123,
  ip: "192.168.1.1",
  timestamp: DateTime.utc_now()
)
```

Long metadata values are automatically truncated based on configuration:
```elixir
# With default config (truncate_threshold: 100, max_length: 500)
dbug("Big data", data: String.duplicate("x", 1000))
# Output: [context] Big data data: "xxxxx... (truncated)"
```

### Value Tracking

Debug values in pipelines without breaking the flow:

```elixir
def process_payment(amount) do
  amount
  |> track("initial_amount")
  |> apply_fees()
  |> track("with_fees")
  |> complete_transaction()
end
```

### Module Configuration

Configure ExDbug behavior per module:

```elixir
use ExDbug,
  context: :payment_processor,
  max_length: 1000,
  truncate_threshold: 200,
  include_timing: true,
  include_stack: false,
  levels: [:debug, :error]
```

### Debug Levels

Control which log levels are enabled:

```elixir
# Only show error messages
use ExDbug,
  context: :critical_system,
  levels: [:error]

# Later in code
error("Critical failure", error: err)  # This shows
dbug("Processing")                     # This doesn't
```

## Output Format

Debug messages follow this format:
```
[Context] Message key1: value1, key2: value2
```

Examples:
```
[payment] Processing payment amount: 100, currency: "USD"
[worker] Job completed status: :ok, duration_ms: 1500
```

## Best Practices

1. Use descriptive context names matching your application structure
2. Include relevant metadata for better debugging context
3. Set appropriate DEBUG patterns for different environments
4. Disable in production for zero overhead
5. Use `track/2` for debugging pipeline transformations

## Production Use

While ExDbug has minimal overhead when disabled, it's recommended to set 
`config :ex_dbug, enabled: false` in production unless debugging is specifically 
needed. This ensures zero runtime cost as debug calls are compiled out completely.

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request

## License

MIT License - see LICENSE.md for details.