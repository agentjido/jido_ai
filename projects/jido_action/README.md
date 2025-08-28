# Jido.Action

[![Hex.pm](https://img.shields.io/hexpm/v/jido_action.svg)](https://hex.pm/packages/jido_action)
[![Hex Docs](https://img.shields.io/badge/hex-docs-lightgreen.svg)](https://hexdocs.pm/jido_action/)
[![CI](https://github.com/agentjido/jido_action/actions/workflows/elixir-ci.yml/badge.svg)](https://github.com/agentjido/jido_action/actions/workflows/elixir-ci.yml)
[![Quality Gate](https://github.com/agentjido/jido_action/actions/workflows/elixir-ci.yml/badge.svg?event=push&job=quality_gate)](https://github.com/agentjido/jido_action/actions/workflows/elixir-ci.yml)
[![License](https://img.shields.io/hexpm/l/jido_action.svg)](https://github.com/agentjido/jido_action/blob/main/LICENSE.md)
[![Coverage Status](https://coveralls.io/repos/github/agentjido/jido_action/badge.svg?branch=main)](https://coveralls.io/github/agentjido/jido_action?branch=main)

> **Composable, validated actions for Elixir applications with built-in AI tool integration**

_`Jido.Action` is part of the [Jido](https://github.com/agentjido/jido) project. Learn more about Jido at [agentjido.xyz](https://agentjido.xyz)._

## Overview

`Jido.Action` is a framework for building composable, validated actions in Elixir. It provides a standardized way to define discrete units of functionality that can be composed into complex workflows, validated at compile and runtime using NimbleOptions schemas, and seamlessly integrated with AI systems through automatic tool generation.

Whether you're building microservices that need structured operations, implementing agent-based systems, or creating AI-powered applications that require reliable function calling, Jido.Action provides the foundation for robust, traceable, and scalable action-driven architecture.

## Why Do I Need Actions?

**Structured Operations in Elixir's Dynamic World**

Elixir excels at building fault-tolerant, concurrent systems, but as applications grow, you often need:

- **Standardized Operation Format**: Raw function calls lack structure, validation, and metadata
- **AI Tool Integration**: Converting functions to LLM-compatible tool definitions manually
- **Workflow Composition**: Building complex multi-step processes from smaller units
- **Parameter Validation**: Ensuring inputs are correct before expensive operations
- **Error Handling**: Consistent error reporting across different operation types
- **Runtime Introspection**: Understanding what operations are available and how they work

```elixir
# Traditional Elixir functions
def process_order(order_id, user_id, options) do
  # No validation, no metadata, no AI integration
  # Error handling is inconsistent
end

# With Jido.Action
defmodule ProcessOrder do
  use Jido.Action,
    name: "process_order",
    description: "Processes a customer order with validation and tracking",
    schema: [
      order_id: [type: :string, required: true],
      user_id: [type: :string, required: true],
      priority: [type: {:in, [:low, :normal, :high]}, default: :normal]
    ]

  def run(params, context) do
    # Params are pre-validated, action is AI-ready, errors are structured
    {:ok, %{status: "processed", order_id: params.order_id}}
  end
end

# Use directly or convert to AI tool
ProcessOrder.to_tool()  # Ready for LLM integration
```

Jido.Action transforms ad-hoc functions into structured, validated, AI-compatible operations that scale from simple tasks to complex agent workflows.

## Key Features

### **Structured Action Definition**
- Compile-time configuration validation
- Runtime parameter validation with NimbleOptions
- Rich metadata including descriptions, categories, and tags
- Automatic JSON serialization support

### **AI Tool Integration**
- Automatic conversion to LLM-compatible tool format
- OpenAI function calling compatible
- Parameter schemas with validation and documentation
- Seamless integration with AI agent frameworks

### **Robust Execution Engine**
- Synchronous and asynchronous execution via `Jido.Exec`
- Automatic retries with exponential backoff
- Timeout handling and cancellation
- Comprehensive error handling and compensation

### **Workflow Composition**
- Instruction-based workflow definition via `Jido.Instruction`
- Parameter normalization and context sharing
- Action chaining and conditional execution
- Built-in workflow primitives

### **Comprehensive Tool Library**
- 25+ pre-built actions for common operations
- File system operations, HTTP requests, arithmetic
- Weather APIs, GitHub integration, workflow primitives
- Robot simulation tools for testing and examples

## Installation

Add `jido_action` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:jido_action, "~> 1.0"}
  ]
end
```

Then run:

```bash
mix deps.get
```

## Quick Start

### 1. Define Your First Action

```elixir
defmodule MyApp.Actions.GreetUser do
  use Jido.Action,
    name: "greet_user",
    description: "Greets a user with a personalized message",
    category: "communication",
    tags: ["greeting", "user"],
    vsn: "1.0.0",
    schema: [
      name: [type: :string, required: true, doc: "User's name"],
      language: [type: {:in, ["en", "es", "fr"]}, default: "en", doc: "Greeting language"]
    ]

  @impl true
  def run(params, _context) do
    greeting = case params.language do
      "en" -> "Hello"
      "es" -> "Hola" 
      "fr" -> "Bonjour"
    end
    
    {:ok, %{message: "#{greeting}, #{params.name}!"}}
  end
end
```

### 2. Execute Actions with Jido.Exec

```elixir
# Synchronous execution
{:ok, result} = Jido.Exec.run(MyApp.Actions.GreetUser, %{name: "Alice"})
# => {:ok, %{message: "Hello, Alice!"}}

# With validation error handling
{:error, reason} = Jido.Exec.run(MyApp.Actions.GreetUser, %{invalid: "params"})
# => {:error, %Jido.Action.Error{type: :validation_error, ...}}

# Asynchronous execution
async_ref = Jido.Exec.run_async(MyApp.Actions.GreetUser, %{name: "Bob"})
{:ok, result} = Jido.Exec.await(async_ref)
```

### 3. Create Workflows with Jido.Instruction

```elixir
# Define a sequence of actions
instructions = [
  MyApp.Actions.ValidateUser,
  {MyApp.Actions.GreetUser, %{name: "Alice", language: "es"}},
  MyApp.Actions.LogActivity
]

# Normalize with shared context
{:ok, workflow} = Jido.Instruction.normalize(instructions, %{
  request_id: "req_123",
  tenant_id: "tenant_456"
})

# Execute the workflow
Enum.each(workflow, fn instruction ->
  Jido.Exec.run(instruction.action, instruction.params, instruction.context)
end)
```

### 4. AI Tool Integration

```elixir
# Convert action to AI tool format
tool_definition = MyApp.Actions.GreetUser.to_tool()

# Returns OpenAI-compatible function definition:
%{
  "name" => "greet_user",
  "description" => "Greets a user with a personalized message",
  "parameters" => %{
    "type" => "object",
    "properties" => %{
      "name" => %{"type" => "string", "description" => "User's name"},
      "language" => %{
        "type" => "string", 
        "enum" => ["en", "es", "fr"],
        "description" => "Greeting language"
      }
    },
    "required" => ["name"]
  }
}

# Use with AI frameworks like OpenAI function calling
# The action can then be executed when the AI calls the tool
```

## Core Components

### Jido.Action
The foundational behavior for defining structured, validated actions. Provides:
- Compile-time configuration validation
- Parameter and output schemas with validation
- Lifecycle hooks for customization
- Automatic AI tool format generation
- JSON serialization support

### Jido.Exec  
The execution engine for running actions reliably. Features:
- Synchronous and asynchronous execution
- Automatic retries with exponential backoff
- Timeout handling and process monitoring
- Comprehensive error handling
- Telemetry integration for monitoring

### Jido.Instruction
The workflow composition system for building complex operations. Enables:
- Multiple input formats (modules, tuples, structs)
- Parameter normalization and validation
- Context sharing across actions
- Action allowlist validation
- Flexible workflow definition patterns

## Bundled Tools

Jido.Action comes with a comprehensive library of pre-built tools organized by category:

### Core Utilities (`Jido.Tools.Basic`)
| Tool | Description | Use Case |
|------|-------------|----------|
| `Sleep` | Pauses execution for specified duration | Delays, rate limiting |
| `Log` | Logs messages with configurable levels | Debugging, monitoring |
| `Todo` | Logs TODO items as placeholders | Development workflow |
| `RandomSleep` | Random delay within specified range | Chaos testing, natural delays |
| `Increment/Decrement` | Numeric operations | Counters, calculations |
| `Noop` | No operation, returns input unchanged | Placeholder actions |
| `Today` | Returns current date in specified format | Date operations |

### Arithmetic Operations (`Jido.Tools.Arithmetic`)
| Tool | Description | Use Case |
|------|-------------|----------|
| `Add` | Adds two numbers | Mathematical operations |
| `Subtract` | Subtracts one number from another | Calculations |
| `Multiply` | Multiplies two numbers | Math workflows |
| `Divide` | Divides with zero-division handling | Safe arithmetic |
| `Square` | Squares a number | Mathematical functions |

### File System Operations (`Jido.Tools.Files`)
| Tool | Description | Use Case |
|------|-------------|----------|
| `WriteFile` | Write content to files with options | File creation, logging |
| `ReadFile` | Read file contents | Data processing |
| `CopyFile` | Copy files between locations | Backup, deployment |
| `MoveFile` | Move/rename files | File organization |
| `DeleteFile` | Delete files/directories (recursive) | Cleanup operations |
| `MakeDirectory` | Create directories (recursive) | Setup operations |
| `ListDirectory` | List directory contents with filtering | File discovery |

### HTTP Operations (`Jido.Tools.ReqTool`)

`ReqTool` is a specialized action that provides a behavior and macro for creating HTTP request actions using the Req library. It offers a standardized way to build HTTP-based actions with configurable URLs, methods, headers, and response processing.

| Tool | Description | Use Case |
|------|-------------|----------|
| HTTP Actions | GET, POST, PUT, DELETE requests with Req library | API integration, webhooks |
| JSON Support | Automatic JSON parsing and response handling | REST API clients |
| Custom Headers | Configurable HTTP headers per action | Authentication, API keys |
| Response Transform | Custom response transformation via callbacks | Data mapping, filtering |
| Action Generation | Macro-based HTTP action creation | Rapid API client development |

### External API Integration
| Tool | Description | Use Case |
|------|-------------|----------|
| `Weather` | National Weather Service API integration | Weather data, forecasts |
| `Github.Issues` | GitHub Issues API (create, list, filter) | Issue management |

### Workflow & Simulation
| Tool | Description | Use Case |
|------|-------------|----------|
| `Workflow` | Multi-step workflow execution | Complex processes |
| `Simplebot` | Robot simulation actions | Testing, examples |

### Specialized Tools
| Tool | Description | Use Case |
|------|-------------|----------|
| Branch/Parallel | Conditional and parallel execution | Complex workflows |
| Error Handling | Compensation and retry mechanisms | Fault tolerance |

## Advanced Features

### Error Handling and Compensation

Actions support sophisticated error handling with optional compensation:

```elixir
defmodule RobustAction do
  use Jido.Action,
    name: "robust_action",
    compensation: [
      enabled: true,
      max_retries: 3,
      timeout: 5000
    ]

  def run(params, context) do
    # Main action logic
    {:ok, result}
  end

  # Called when errors occur if compensation is enabled
  def on_error(failed_params, error, context, opts) do
    # Perform rollback/cleanup operations
    {:ok, %{compensated: true, original_error: error}}
  end
end
```

### Lifecycle Hooks

Customize action behavior with lifecycle hooks:

```elixir
defmodule CustomAction do
  use Jido.Action, name: "custom_action"

  def on_before_validate_params(params) do
    # Transform params before validation
    {:ok, transformed_params}
  end

  def on_after_validate_params(params) do
    # Enrich params after validation
    {:ok, enriched_params}
  end

  def on_after_run(result) do
    # Post-process results
    {:ok, enhanced_result}
  end
end
```

### Telemetry Integration

Actions emit telemetry events for monitoring:

```elixir
# Attach telemetry handlers
:telemetry.attach("action-handler", [:jido, :action, :complete], fn event, measurements, metadata, config ->
  # Handle action completion events
  Logger.info("Action completed: #{metadata.action}")
end, %{})
```

## Testing

Test actions directly or within the execution framework:

```elixir
defmodule MyActionTest do
  use ExUnit.Case

  test "action validates parameters" do
    assert {:error, _} = MyAction.validate_params(%{invalid: "params"})
    assert {:ok, _} = MyAction.validate_params(%{valid: "params"})
  end

  test "action execution" do
    assert {:ok, result} = Jido.Exec.run(MyAction, %{valid: "params"})
    assert result.status == "success"
  end

  test "async action execution" do
    async_ref = Jido.Exec.run_async(MyAction, %{valid: "params"})
    assert {:ok, result} = Jido.Exec.await(async_ref, 5000)
  end
end
```

## Configuration

Configure defaults in your application:

```elixir
# config/config.exs
config :jido_action,
  default_timeout: 10_000,
  default_max_retries: 3,
  default_backoff: 500
```

## Maintenance and Support

![Maintenance](https://img.shields.io/maintenance/yes/2024.svg)

Jido Action is actively maintained with the following commitments:

- **Issue Response**: Best-effort response within 7 days for bugs, 24 hours for security issues
- **Security Updates**: Critical security fixes within 7 days, backported to supported versions
- **Release Cadence**: Monthly minor releases, bi-weekly patch releases as needed
- **Long-term Support**: Major versions supported for minimum 18 months

For detailed information about our maintenance policy, support windows, and issue response times, see our [GitHub Issues](https://github.com/agentjido/jido_action/issues).

## Contributing

We welcome contributions! Please see our [GitHub repository](https://github.com/agentjido/jido_action) for details.

## License

Copyright 2024 Mike Hostetler

Licensed under the Apache License, Version 2.0. See [LICENSE.md](LICENSE.md) for details.

For information about dependency licenses, see the [LICENSE.md](LICENSE.md) file.

## Links

- **Documentation**: [https://hexdocs.pm/jido_action](https://hexdocs.pm/jido_action)
- **GitHub**: [https://github.com/agentjido/jido_action](https://github.com/agentjido/jido_action)
- **AgentJido**: [https://agentjido.xyz](https://agentjido.xyz)
- **Jido Workbench**: [https://github.com/agentjido/jido_workbench](https://github.com/agentjido/jido_workbench)
