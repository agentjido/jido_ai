# Plugins and Extensions

Plugins enable AI models to interact with external tools, APIs, and services, extending their capabilities beyond text generation.

## ⚠️ Security Notice

**Plugin configurations are validated with security controls:**

- **Command Whitelist**: MCP servers can only execute approved commands (npx, node, python3, python)
- **Name Validation**: Plugin names must be alphanumeric with hyphens/underscores only
- **Environment Filtering**: Blocks environment variables containing secret patterns (KEY, SECRET, TOKEN, etc.)
- **Logging**: Security violations are logged for monitoring

Never accept plugin configurations from untrusted sources without additional validation.

## Overview

Plugins allow models to:
- **Call External APIs**: Weather, stock prices, database queries
- **Execute Tools**: File operations, calculations, searches
- **Integrate Services**: CRM, analytics, monitoring
- **Access Real-time Data**: Current information beyond training data

## Supported Plugin Systems

| Provider | Plugin System | Configuration | Best For |
|----------|---------------|---------------|----------|
| **OpenAI** | GPT Actions | JSON Schema | API integrations |
| **Anthropic** | MCP (Model Context Protocol) | Server config | Tool servers |
| **Google** | Gemini Extensions | Extension spec | Built-in tools |

## Quick Start

### OpenAI GPT Actions

```elixir
alias Jido.AI.Features.Plugins

# 1. Define plugin
weather_plugin = %{
  type: :action,
  name: "get_weather",
  description: "Get current weather for a location",
  schema: %{
    type: "object",
    properties: %{
      location: %{type: "string", description: "City name"}
    },
    required: ["location"]
  }
}

# 2. Configure plugin
{:ok, config} = Plugins.configure_plugin(weather_plugin, :openai)

# 3. Build options
{:ok, opts} = Plugins.build_plugin_options([weather_plugin], %{}, :openai)

# 4. Use with chat
{:ok, response} = Jido.AI.chat(
  "openai:gpt-4",
  "What's the weather in Paris?",
  opts
)

# 5. Extract plugin results
{:ok, results} = Plugins.extract_results(response.raw, :openai)
```

### Anthropic MCP Servers

```elixir
# Security-validated MCP server configuration
database_plugin = %{
  type: :mcp_server,
  name: "database",
  command: "npx",  # Must be in whitelist
  args: ["@modelcontextprotocol/server-postgres"],
  env: %{
    "DATABASE_URL" => get_database_url(),  # ❌ Would be blocked - contains pattern
    "NODE_ENV" => "production"  # ✅ Allowed
  }
}

# This will fail validation due to DATABASE_URL
case Plugins.configure_plugin(database_plugin, :anthropic) do
  {:ok, config} -> IO.puts "Configured"
  {:error, reason} -> IO.puts "Failed: #{reason}"
end

# Correct approach - use allowed environment variables
safe_plugin = %{
  type: :mcp_server,
  name: "database",
  command: "npx",
  args: ["@modelcontextprotocol/server-postgres"],
  env: %{
    "NODE_ENV" => "production",
    "DB_HOST" => "localhost"  # ✅ Allowed
  }
}

{:ok, opts} = Plugins.build_plugin_options([safe_plugin], %{}, :anthropic)
```

### Google Gemini Extensions

```elixir
# Google has built-in extensions
search_plugin = %{
  type: :extension,
  name: "google_search",
  description: "Search the web",
  parameters: %{}
}

{:ok, opts} = Plugins.build_plugin_options([search_plugin], %{}, :google)

{:ok, response} = Jido.AI.chat(
  "vertex:gemini-1.5-pro",
  "Search for latest Elixir news",
  opts
)
```

## Plugin Configuration

### OpenAI GPT Actions

GPT Actions allow models to call external APIs:

```elixir
# API plugin with authentication
api_plugin = %{
  type: :action,
  name: "get_user_data",
  description: "Fetch user data from our API",
  schema: %{
    type: "object",
    properties: %{
      user_id: %{type: "string"},
      include_profile: %{type: "boolean", default: true}
    },
    required: ["user_id"]
  },
  authentication: %{
    type: "api_key",
    header_name: "X-API-Key"
  }
}

{:ok, config} = Plugins.configure_plugin(api_plugin, :openai)
```

### Anthropic MCP Servers

MCP servers provide tool capabilities:

```elixir
# File system MCP server (security-validated)
filesystem_plugin = %{
  type: :mcp_server,
  name: "filesystem",
  command: "npx",  # ✅ Allowed command
  args: ["@modelcontextprotocol/server-filesystem", "/safe/directory"],
  env: %{
    "NODE_ENV" => "production"  # ✅ No secret patterns
  }
}

case Plugins.configure_plugin(filesystem_plugin, :anthropic) do
  {:ok, config} ->
    # MCP server configured
    {:ok, opts} = Plugins.build_plugin_options([filesystem_plugin], %{}, :anthropic)

    Jido.AI.chat(
      "anthropic:claude-3-sonnet",
      "List files in the directory",
      opts
    )

  {:error, reason} ->
    IO.puts "Configuration failed: #{reason}"
end
```

### Google Gemini Extensions

```elixir
# Discover available extensions
extensions = Plugins.discover(:google)
# ["code_execution", "google_search"]

# Use code execution extension
code_exec_plugin = %{
  type: :extension,
  name: "code_execution",
  description: "Execute Python code",
  parameters: %{
    language: "python"
  }
}

{:ok, opts} = Plugins.build_plugin_options([code_exec_plugin], %{}, :google)
```

## Advanced Patterns

### 1. Multi-Tool Workflows

Use multiple plugins in sequence:

```elixir
defmodule MyApp.MultiToolWorkflow do
  alias Jido.AI.Features.Plugins

  def analyze_user_behavior(user_id) do
    # Define plugins
    plugins = [
      %{
        type: :action,
        name: "get_user_data",
        description: "Get user profile and activity",
        schema: user_schema()
      },
      %{
        type: :action,
        name: "get_analytics",
        description: "Get user analytics data",
        schema: analytics_schema()
      },
      %{
        type: :action,
        name: "generate_report",
        description: "Generate analysis report",
        schema: report_schema()
      }
    ]

    # Configure plugins
    {:ok, opts} = Plugins.build_plugin_options(plugins, %{}, :openai)

    # Model will orchestrate plugin calls
    prompt = """
    Analyze user behavior for user #{user_id}:
    1. Get their profile data
    2. Fetch their analytics
    3. Generate a summary report
    """

    Jido.AI.chat("openai:gpt-4", prompt, opts)
  end

  defp user_schema, do: %{type: "object", properties: %{user_id: %{type: "string"}}}
  defp analytics_schema, do: %{type: "object", properties: %{user_id: %{type: "string"}}}
  defp report_schema, do: %{type: "object", properties: %{data: %{type: "object"}}}
end
```

### 2. Dynamic Plugin Loading

Load plugins based on context:

```elixir
defmodule MyApp.DynamicPlugins do
  def chat_with_context(prompt, context) do
    # Select plugins based on context
    plugins = select_plugins_for_context(context)

    {:ok, opts} = Plugins.build_plugin_options(plugins, %{}, :openai)
    Jido.AI.chat("openai:gpt-4", prompt, opts)
  end

  defp select_plugins_for_context(context) do
    case context do
      :financial ->
        [stock_plugin(), currency_plugin(), calculator_plugin()]

      :customer_service ->
        [crm_plugin(), ticket_plugin(), knowledge_base_plugin()]

      :development ->
        [github_plugin(), jira_plugin(), docs_plugin()]

      _ ->
        [search_plugin()]
    end
  end

  defp stock_plugin do
    %{
      type: :action,
      name: "get_stock_price",
      description: "Get current stock price",
      schema: %{type: "object", properties: %{symbol: %{type: "string"}}}
    }
  end

  # ... other plugin definitions
end
```

### 3. Plugin Result Processing

Process and validate plugin results:

```elixir
defmodule MyApp.PluginResultProcessor do
  def execute_with_validation(prompt, plugins) do
    {:ok, opts} = Plugins.build_plugin_options(plugins, %{}, :openai)

    case Jido.AI.chat("openai:gpt-4", prompt, opts) do
      {:ok, response} ->
        {:ok, results} = Plugins.extract_results(response.raw, :openai)

        # Validate each plugin result
        case validate_results(results) do
          :ok ->
            {:ok, response, results}

          {:error, invalid_results} ->
            # Retry with corrected prompt
            retry_with_corrections(prompt, invalid_results, opts)
        end

      error -> error
    end
  end

  defp validate_results(results) do
    invalid = Enum.filter(results, fn result ->
      not valid_result?(result)
    end)

    if Enum.empty?(invalid) do
      :ok
    else
      {:error, invalid}
    end
  end

  defp valid_result?(%{result: result}) when is_nil(result), do: false
  defp valid_result?(%{result: %{"error" => _}}), do: false
  defp valid_result?(_), do: true

  defp retry_with_corrections(prompt, invalid_results, opts) do
    correction_prompt = """
    #{prompt}

    Previous plugin calls failed:
    #{format_failures(invalid_results)}

    Please try again with correct parameters.
    """

    Jido.AI.chat("openai:gpt-4", correction_prompt, opts)
  end

  defp format_failures(results) do
    Enum.map_join(results, "\n", fn result ->
      "- #{result.plugin}: #{inspect(result.arguments)}"
    end)
  end
end
```

### 4. Plugin Chaining

Chain plugin results for complex workflows:

```elixir
defmodule MyApp.PluginChain do
  def execute_chain(steps) do
    Enum.reduce_while(steps, {:ok, nil}, fn step, {:ok, previous_result} ->
      case execute_step(step, previous_result) do
        {:ok, result} -> {:cont, {:ok, result}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp execute_step({plugin, prompt_template}, previous_result) do
    prompt = build_prompt(prompt_template, previous_result)

    {:ok, opts} = Plugins.build_plugin_options([plugin], %{}, :openai)
    {:ok, response} = Jido.AI.chat("openai:gpt-4", prompt, opts)
    {:ok, results} = Plugins.extract_results(response.raw, :openai)

    {:ok, %{response: response, plugin_results: results}}
  end

  defp build_prompt(template, nil), do: template
  defp build_prompt(template, previous) do
    String.replace(template, "{{previous_result}}", inspect(previous))
  end
end

# Usage
steps = [
  {user_plugin, "Get data for user {{user_id}}"},
  {analytics_plugin, "Analyze this user data: {{previous_result}}"},
  {report_plugin, "Generate report from analysis: {{previous_result}}"}
]

MyApp.PluginChain.execute_chain(steps)
```

### 5. Secure Plugin Execution

Additional security layers for plugins:

```elixir
defmodule MyApp.SecurePlugins do
  require Logger

  def execute_secure(prompt, plugins, user_id) do
    # 1. Validate plugins
    case validate_plugins(plugins) do
      :ok ->
        # 2. Check permissions
        case check_permissions(user_id, plugins) do
          :ok ->
            # 3. Execute with audit logging
            execute_with_audit(prompt, plugins, user_id)

          {:error, reason} ->
            {:error, {:permission_denied, reason}}
        end

      {:error, reason} ->
        {:error, {:invalid_plugin, reason}}
    end
  end

  defp validate_plugins(plugins) do
    # Additional validation beyond built-in checks
    Enum.reduce_while(plugins, :ok, fn plugin, _acc ->
      cond do
        # Check plugin whitelist
        not plugin_whitelisted?(plugin.name) ->
          {:halt, {:error, "Plugin #{plugin.name} not whitelisted"}}

        # Check for suspicious patterns
        suspicious_plugin?(plugin) ->
          {:halt, {:error, "Plugin contains suspicious patterns"}}

        true ->
          {:cont, :ok}
      end
    end)
  end

  defp check_permissions(user_id, plugins) do
    # Check if user has permission to use these plugins
    Enum.reduce_while(plugins, :ok, fn plugin, _acc ->
      if user_can_use_plugin?(user_id, plugin.name) do
        {:cont, :ok}
      else
        {:halt, {:error, "User #{user_id} cannot use plugin #{plugin.name}"}}
      end
    end)
  end

  defp execute_with_audit(prompt, plugins, user_id) do
    execution_id = generate_id()

    Logger.info("Plugin execution started", %{
      execution_id: execution_id,
      user_id: user_id,
      plugins: Enum.map(plugins, & &1.name)
    })

    {:ok, opts} = Plugins.build_plugin_options(plugins, %{}, :openai)
    result = Jido.AI.chat("openai:gpt-4", prompt, opts)

    Logger.info("Plugin execution completed", %{
      execution_id: execution_id,
      success: match?({:ok, _}, result)
    })

    result
  end

  defp plugin_whitelisted?(name) do
    whitelist = Application.get_env(:my_app, :plugin_whitelist, [])
    name in whitelist
  end

  defp suspicious_plugin?(_plugin), do: false
  defp user_can_use_plugin?(_user_id, _plugin_name), do: true
  defp generate_id, do: :crypto.strong_rand_bytes(16) |> Base.encode16()
end
```

## Security Best Practices

### 1. Validate Plugin Names

```elixir
# ✅ Valid plugin names
%{name: "get_weather"}          # Alphanumeric
%{name: "fetch-user-data"}      # With hyphens
%{name: "db_query"}             # With underscores

# ❌ Invalid plugin names (will be rejected)
%{name: "get weather"}          # Spaces
%{name: "fetch@data"}           # Special chars
%{name: "../../../etc/passwd"}  # Path traversal
```

### 2. MCP Command Whitelist

```elixir
# ✅ Allowed commands
%{command: "npx"}      # Allowed
%{command: "node"}     # Allowed
%{command: "python3"}  # Allowed
%{command: "python"}   # Allowed

# ❌ Blocked commands
%{command: "bash"}     # Not in whitelist
%{command: "sh"}       # Not in whitelist
%{command: "curl"}     # Not in whitelist
```

### 3. Environment Variable Filtering

```elixir
# ✅ Allowed environment variables
%{env: %{
  "NODE_ENV" => "production",
  "PORT" => "3000",
  "DEBUG" => "false"
}}

# ❌ Blocked environment variables (will be rejected)
%{env: %{
  "API_KEY" => "secret",      # Contains "KEY"
  "DB_PASSWORD" => "pass",    # Contains "PASSWORD"
  "AUTH_TOKEN" => "token"     # Contains "TOKEN"
}}
```

### 4. Rate Limiting

```elixir
defmodule MyApp.RateLimitedPlugins do
  use GenServer

  @rate_limit 100  # per minute
  @window 60_000   # 1 minute in ms

  def execute(prompt, plugins, user_id) do
    case check_rate_limit(user_id) do
      :ok ->
        increment_usage(user_id)
        {:ok, opts} = Plugins.build_plugin_options(plugins, %{}, :openai)
        Jido.AI.chat("openai:gpt-4", prompt, opts)

      {:error, :rate_limited} ->
        {:error, :rate_limit_exceeded}
    end
  end

  defp check_rate_limit(user_id) do
    # Check if user has exceeded rate limit
    :ok
  end

  defp increment_usage(user_id) do
    # Track usage
    :ok
  end
end
```

## Troubleshooting

### Plugin Configuration Errors

```elixir
# Error: Invalid plugin name
{:error, "Invalid plugin name: 'get weather'"}

# Solution: Use alphanumeric with hyphens/underscores
%{name: "get-weather"}  # ✅
%{name: "get_weather"}  # ✅
```

### MCP Command Blocked

```elixir
# Error: Command 'bash' not allowed
{:error, "Command 'bash' not allowed. Permitted commands: [...]"}

# Solution: Use allowed commands
%{command: "npx"}  # ✅
```

### Environment Variable Rejected

```elixir
# Error: Environment variable 'API_KEY' contains forbidden pattern
{:error, "Environment variable 'API_KEY' contains forbidden pattern..."}

# Solution: Use non-secret environment variables
%{env: %{"CONFIG_PATH" => "/config"}}  # ✅
```

### Plugin Not Found

```elixir
# Check available plugins
extensions = Plugins.discover(:google)
IO.inspect extensions

# Ensure plugin name matches available plugins
```

## Next Steps

- [Code Execution](code-execution.md) - Enable code interpretation
- [RAG Integration](rag-integration.md) - Document-enhanced responses
- [Fine-Tuning](fine-tuning.md) - Custom models
- [Provider Matrix](../providers/provider-matrix.md) - Compare providers
