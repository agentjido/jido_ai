# AGENT.md - Jido Eval Development Guide

Jido Eval is an Elixir package for evaluating LLMs. It follows the Ragas SDK (Python) pattern. It is designed for use within the Jido Ecosystem.

## Ragas Version

This package is based on Ragas version 0.3.1, available as of 2025-08-18 at https://github.com/explodinggradients/ragas/tree/v0.3.1

## Commands

- **Test**: `mix test` (all), `mix test test/path/to/specific_test.exs` (single file), `mix test --trace` (verbose)
- **Lint**: `mix credo` (basic), `mix credo --strict` (strict mode)
- **Format**: `mix format` (format code), `mix format --check-formatted` (verify formatting)
- **Quality**: `mix quality` or `mix q` (runs format, compile, dialyzer, credo, doctor, docs)
- **Compile**: `mix compile` (basic), `mix compile --warnings-as-errors` (strict)
- **Type Check**: `mix dialyzer --format dialyxir`
- **Coverage**: `mix test --cover` (basic), `mix coveralls.html` (HTML report)
- **Docs**: `mix docs` (generate documentation)

## SDLC

- **Coverage Goal**: Test coverage goal should be 80%+
- **Code Quality**: Use `mix quality` to run all checks
  - Fix all compiler warnings
  - Fix all dialyzer warnings
  - Add `@type` to all custom types
  - Add `@spec` to all public functions
  - Add `@doc` to all public functions and `@moduledoc` to all modules

## Code Style

- **Formatting**: Uses [`mix format`](.formatter.exs), line length max 120 chars
- **Types**: Add `@spec` to all public functions, use `@type` for custom types
- **Docs**: `@moduledoc` for modules, `@doc` for public functions with examples
- **Testing**: Mirror lib structure in test/, use ExUnit with async when possible, tag slow/integration tests
- **HTTP Testing**: Use Req.Test for HTTP mocking instead of Mimic - provides cleaner stubs and better integration
- **Error Handling**: Return `{:ok, result}` or `{:error, reason}` tuples, use `with` for complex flows
- **Imports**: Group aliases at module top, prefer explicit over wildcard imports
- **Naming**: `snake_case` for functions/variables, `PascalCase` for modules
- **Logging**: Avoid Logger metadata - integrate all fields into log message strings instead of using keyword lists

## Architecture

Jido Eval follows a **pluggable component architecture** with clean separation of concerns:

- **Core Data Layer**: Sample structures and Dataset protocol for flexible data sources
- **Component System**: Pluggable behaviours for reporters, stores, broadcasters, processors, middleware
- **Execution Engine**: OTP-supervised evaluation with fault isolation and concurrency control
- **LLM Integration**: Retry-enabled wrapper around jido_ai with caching and error normalization

## Public API Overview

### Simple Evaluation (Ragas-compatible)
```elixir
# Quick evaluation with defaults
{:ok, result} = Jido.Eval.evaluate(dataset)

# With specific metrics
{:ok, result} = Jido.Eval.evaluate(dataset, metrics: [:faithfulness, :context_precision])
```

### Advanced Configuration
```elixir
# Enterprise features with pluggable components
{:ok, result} = Jido.Eval.evaluate(dataset, 
  metrics: [:faithfulness, :context_precision],
  llm: "openai:gpt-4o",
  run_config: %Jido.Eval.RunConfig{timeout: 30_000},
  reporters: [{MyApp.JSONReporter, format: :json}],
  stores: [{MyApp.PostgresStore, table: "evaluations"}],
  broadcasters: [{Phoenix.PubSub, topic: "evals"}]
)
```

### Async Evaluation with Monitoring
```elixir
# Async evaluation with real-time monitoring
{:ok, run_id} = Jido.Eval.evaluate(dataset, sync: false)
:telemetry.attach([:jido, :eval, :progress], fn event, measurements, metadata, _ ->
  IO.puts("Progress: #{metadata.completed}/#{metadata.total}")
end)
```

## Data Architecture

### Sample Structures
- **`Jido.Eval.Sample.SingleTurn`**: Single Q&A interactions with context, response, and metadata
- **`Jido.Eval.Sample.MultiTurn`**: Multi-turn conversations using `[Jido.AI.Message.t()]`
- **Helper Functions**: Convert between string and Message formats, validation with clear errors

### Dataset Protocol
- **`Jido.Eval.Dataset`**: Protocol for pluggable data sources (to_stream/1, sample_type/1, count/1)
- **Built-in Adapters**: InMemory (lists), JSONL (streaming), CSV (single-turn only)
- **Memory Efficient**: Streaming preserves memory usage regardless of dataset size

### Configuration System
- **`Jido.Eval.Config`**: Runtime configuration with pluggable components
- **`Jido.Eval.RunConfig`**: Execution parameters (timeout, workers, retry policy)
- **`Jido.Eval.RetryPolicy`**: Retry behavior with exponential backoff and jitter

### Component Registry
- **`Jido.Eval.ComponentRegistry`**: ETS-based registry for hot-reloadable components
- **Component Types**: reporter, store, broadcaster, processor, middleware
- **Runtime Discovery**: Dynamic component lookup and registration

## Jido AI Integration

This package uses `jido_ai` for all LLM interactions. Follow these patterns:

### Text Generation

```elixir
# Simple text generation
{:ok, response} = Jido.AI.generate_text("openai:gpt-4o", "Evaluate this response")

# With rich messages
import Jido.AI.Messages
messages = [
  system("You are an evaluation expert"),
  user("Rate this response: #{response}")
]
{:ok, evaluation} = Jido.AI.generate_text("openai:gpt-4o", messages)
```

### Structured Data Generation

```elixir
# Schema-validated evaluation results
schema = [
  score: [type: :float, required: true],
  reasoning: [type: :string, required: true],
  categories: [type: {:list, :string}, default: []]
]

{:ok, result} = Jido.AI.generate_object(
  "openai:gpt-4o",
  "Evaluate this response",
  schema
)
```

### Model Specifications

This package uses `jido_ai` for all LLM interactions. The string format `"provider:model"` is the canonical way to specify models in the Jido ecosystem and is by design:

- String: `"openai:gpt-4o"` or `"anthropic:claude-3-5-sonnet-20241022"` (primary format)
- Tuple: `{:openai, model: "gpt-4o", temperature: 0.1}` (for evaluations requiring consistency)
- Struct: `%Jido.AI.Model{}` (when building complex configurations)

The string format provides a clean, consistent interface across all Jido packages.

### Configuration

Access provider keys via:
- `Jido.AI.api_key(:openai)` - Get API key for provider
- `Jido.AI.config([:openai, :api_key], nil)` - Get config with fallback

