# Security Guide

**Prerequisites**: [Configuration Guide](configuration.md)

Secure your Jido Action applications with proper input validation, resource limits, access controls, and protection against common vulnerabilities.

## Input Validation & Sanitization

### Schema-Based Validation

Actions automatically validate inputs using NimbleOptions schemas:

```elixir
defmodule MyApp.Actions.SecureUser do
  use Jido.Action,
    name: "secure_user",
    schema: [
      # Type validation prevents injection attacks
      user_id: [
        type: :string,
        required: true,
        # Regex validation for format
        matches: ~r/^[a-zA-Z0-9_-]{1,50}$/
      ],
      email: [
        type: :string,
        required: true,
        # Length limits prevent DoS
        max_length: 320
      ],
      age: [
        type: :integer,
        required: true,
        # Range validation
        min: 13,
        max: 150
      ],
      # Whitelist allowed values
      role: [
        type: :atom,
        in: [:user, :admin, :moderator],
        default: :user
      ]
    ]

  def run(params, _context) do
    # Additional business logic validation
    with :ok <- validate_email_domain(params.email),
         :ok <- check_user_permissions(params.role) do
      {:ok, process_user(params)}
    end
  end

  defp validate_email_domain(email) do
    domain = email |> String.split("@") |> List.last()
    
    if domain in allowed_domains() do
      :ok
    else
      {:error, Jido.Action.Error.validation_error(
        "Email domain not allowed",
        %{domain: domain}
      )}
    end
  end
end
```

### Input Sanitization

```elixir
defmodule MyApp.Actions.SanitizeInput do
  use Jido.Action,
    schema: [
      content: [type: :string, required: true],
      format: [type: :atom, in: [:html, :markdown, :text], default: :text]
    ]

  @impl true
  def on_before_validate_params(params) do
    # Sanitize before validation
    sanitized = Map.update!(params, :content, &sanitize_content/1)
    {:ok, sanitized}
  end

  def run(params, _context) do
    # Content is already sanitized
    {:ok, %{content: params.content, length: String.length(params.content)}}
  end

  defp sanitize_content(content) do
    content
    |> String.trim()
    |> remove_dangerous_characters()
    |> limit_length(10_000)
  end

  defp remove_dangerous_characters(content) do
    # Remove or escape dangerous characters
    content
    |> String.replace(~r/[<>\"'&]/, "")
    |> String.replace(~r/javascript:/i, "")
    |> String.replace(~r/data:/i, "")
  end

  defp limit_length(content, max_length) do
    if String.length(content) > max_length do
      String.slice(content, 0, max_length)
    else
      content
    end
  end
end
```

## Resource Limits

### Memory Limits

```elixir
defmodule MyApp.Actions.LimitedMemory do
  use Jido.Action,
    schema: [data: [type: :string, required: true]]

  def run(params, _context) do
    # Check input size before processing
    if byte_size(params.data) > max_input_size() do
      {:error, Jido.Action.Error.validation_error(
        "Input too large",
        %{size: byte_size(params.data), max: max_input_size()}
      )}
    else
      process_data_safely(params.data)
    end
  end

  defp max_input_size, do: 1_000_000  # 1MB

  defp process_data_safely(data) do
    # Monitor memory usage during processing
    start_memory = :erlang.memory(:processes)
    
    result = process_data(data)
    
    end_memory = :erlang.memory(:processes)
    memory_used = end_memory - start_memory
    
    if memory_used > max_memory_per_action() do
      Logger.warning("High memory usage detected",
        action: __MODULE__,
        memory_used: memory_used
      )
    end
    
    {:ok, result}
  end

  defp max_memory_per_action, do: 10_000_000  # 10MB
end
```

### Time Limits

```elixir
# Use execution engine timeouts
{:ok, result} = Jido.Exec.run(
  MyApp.Actions.TimeLimited,
  params,
  context,
  timeout: 5_000  # Prevent long-running operations
)

# Per-action timeout configuration
defmodule MyApp.Actions.TimeLimited do
  use Jido.Action,
    # Set strict timeout for this action
    default_timeout: 3_000,
    schema: [operation: [type: :atom, required: true]]

  def run(params, _context) do
    # Implementation with internal timeouts
    Task.async(fn -> expensive_operation(params.operation) end)
    |> Task.await(2_000)  # Internal timeout shorter than action timeout
  rescue
    :timeout ->
      {:error, Jido.Action.Error.timeout_error("Operation timed out internally")}
  end
end
```

### File System Restrictions

```elixir
defmodule MyApp.Actions.SecureFileOp do
  use Jido.Action,
    schema: [
      path: [type: :string, required: true],
      content: [type: :string, required: true]
    ]

  def run(params, _context) do
    with :ok <- validate_file_path(params.path),
         :ok <- validate_file_size(params.content),
         {:ok, _} <- write_file_safely(params.path, params.content) do
      {:ok, %{file: params.path, size: byte_size(params.content)}}
    end
  end

  defp validate_file_path(path) do
    allowed_dirs = ["/tmp/uploads", "/var/data/safe"]
    
    # Convert to absolute path and normalize
    abs_path = Path.expand(path)
    
    # Check if path is within allowed directories
    if Enum.any?(allowed_dirs, &String.starts_with?(abs_path, &1)) do
      :ok
    else
      {:error, Jido.Action.Error.validation_error(
        "File path not allowed",
        %{path: path, allowed_dirs: allowed_dirs}
      )}
    end
  end

  defp validate_file_size(content) do
    max_size = 1_000_000  # 1MB
    
    if byte_size(content) > max_size do
      {:error, Jido.Action.Error.validation_error(
        "File too large",
        %{size: byte_size(content), max: max_size}
      )}
    else
      :ok
    end
  end

  defp write_file_safely(path, content) do
    # Ensure directory exists (but only in allowed paths)
    case File.mkdir_p(Path.dirname(path)) do
      :ok -> File.write(path, content)
      error -> error
    end
  end
end
```

## Network Security

### HTTP Request Validation

```elixir
defmodule MyApp.Actions.SecureHttpCall do
  use Jido.Action,
    schema: [
      url: [type: :string, required: true],
      method: [type: :atom, in: [:get, :post, :put, :delete], default: :get],
      headers: [type: :map, default: %{}],
      body: [type: :string, default: ""]
    ]

  def run(params, _context) do
    with :ok <- validate_url(params.url),
         :ok <- validate_headers(params.headers),
         {:ok, response} <- make_request(params) do
      {:ok, response}
    end
  end

  defp validate_url(url) do
    case URI.parse(url) do
      %URI{scheme: scheme, host: host} when scheme in ["http", "https"] and not is_nil(host) ->
        if allowed_host?(host) do
          :ok
        else
          {:error, Jido.Action.Error.validation_error(
            "Host not allowed",
            %{host: host}
          )}
        end
      
      _ ->
        {:error, Jido.Action.Error.validation_error("Invalid URL format")}
    end
  end

  defp allowed_host?(host) do
    # Block internal/private addresses
    blocked_patterns = [
      ~r/^localhost$/i,
      ~r/^127\./,
      ~r/^10\./,
      ~r/^172\.(1[6-9]|2[0-9]|3[01])\./,
      ~r/^192\.168\./,
      ~r/^169\.254\./  # Link-local
    ]
    
    # Allow specific external hosts
    allowed_hosts = [
      "api.example.com",
      "secure-service.com"
    ]
    
    host in allowed_hosts and 
      not Enum.any?(blocked_patterns, &Regex.match?(&1, host))
  end

  defp validate_headers(headers) do
    # Prevent header injection
    dangerous_headers = ["host", "authorization", "cookie"]
    
    if Enum.any?(headers, fn {key, _} -> 
      String.downcase(key) in dangerous_headers 
    end) do
      {:error, Jido.Action.Error.validation_error("Dangerous headers not allowed")}
    else
      :ok
    end
  end

  defp make_request(params) do
    # Make request with security settings
    options = [
      timeout: 5_000,
      max_redirects: 3,
      # Disable dangerous features
      follow_redirects: false,
      ssl_verify: :verify_peer
    ]
    
    HTTPoison.request(
      params.method,
      params.url,
      params.body,
      params.headers,
      options
    )
  end
end
```

## Access Control

### Context-Based Authorization

```elixir
defmodule MyApp.Actions.AuthorizedAction do
  use Jido.Action,
    schema: [
      resource_id: [type: :string, required: true],
      action: [type: :atom, in: [:read, :write, :delete], required: true]
    ]

  def run(params, context) do
    with :ok <- authenticate_user(context),
         :ok <- authorize_action(context, params) do
      perform_action(params, context)
    end
  end

  defp authenticate_user(context) do
    case Map.get(context, :user_id) do
      nil -> 
        {:error, Jido.Action.Error.execution_error("Authentication required")}
      user_id when is_binary(user_id) -> 
        :ok
      _ -> 
        {:error, Jido.Action.Error.execution_error("Invalid authentication")}
    end
  end

  defp authorize_action(context, params) do
    user_id = context.user_id
    resource_id = params.resource_id
    action = params.action
    
    if has_permission?(user_id, resource_id, action) do
      :ok
    else
      {:error, Jido.Action.Error.execution_error(
        "Insufficient permissions",
        %{user_id: user_id, resource_id: resource_id, action: action}
      )}
    end
  end

  defp has_permission?(user_id, resource_id, action) do
    # Check permissions in database/cache
    MyApp.Permissions.check(user_id, resource_id, action)
  end
end
```

### Role-Based Access Control

```elixir
defmodule MyApp.Security.RBAC do
  @admin_actions [:create_user, :delete_user, :view_all_data]
  @moderator_actions [:edit_content, :ban_user, :view_reports]
  @user_actions [:view_profile, :edit_own_profile, :create_content]

  def authorize(user_role, action) do
    allowed_actions = case user_role do
      :admin -> @admin_actions ++ @moderator_actions ++ @user_actions
      :moderator -> @moderator_actions ++ @user_actions
      :user -> @user_actions
      _ -> []
    end
    
    if action in allowed_actions do
      :ok
    else
      {:error, "Action #{action} not allowed for role #{user_role}"}
    end
  end
end

defmodule MyApp.Actions.RBACAction do
  use Jido.Action,
    schema: [data: [type: :any, required: true]]

  # Define required role for this action
  @required_role :moderator

  def run(params, context) do
    with :ok <- check_role_authorization(context) do
      perform_moderation_action(params.data)
    end
  end

  defp check_role_authorization(context) do
    user_role = Map.get(context, :user_role, :guest)
    MyApp.Security.RBAC.authorize(user_role, @required_role)
  end
end
```

## Secrets Management

### Environment Variable Handling

```elixir
defmodule MyApp.Secrets do
  @doc "Get secret with validation"
  def get_secret!(key) do
    case System.get_env(key) do
      nil -> 
        raise "Missing required secret: #{key}"
      "" -> 
        raise "Empty secret: #{key}"
      secret when byte_size(secret) < 8 ->
        raise "Secret too short: #{key}"
      secret -> 
        secret
    end
  end

  @doc "Get optional secret with default"
  def get_secret(key, default \\ nil) do
    case System.get_env(key) do
      nil -> default
      "" -> default
      secret -> secret
    end
  end
end

defmodule MyApp.Actions.UseSecrets do
  use Jido.Action,
    schema: [operation: [type: :string, required: true]]

  def run(params, _context) do
    # Get secrets securely
    api_key = MyApp.Secrets.get_secret!("API_KEY")
    endpoint = MyApp.Secrets.get_secret("API_ENDPOINT", "https://api.default.com")
    
    # Use secrets in action
    perform_api_operation(params.operation, api_key, endpoint)
  end

  # Never log secrets
  defp perform_api_operation(operation, api_key, endpoint) do
    Logger.info("Performing API operation", operation: operation, endpoint: endpoint)
    # Note: api_key is NOT logged
    
    # Implementation...
    {:ok, %{status: "completed"}}
  end
end
```

### Secret Rotation

```elixir
defmodule MyApp.SecretRotation do
  @doc "Support multiple API keys for rotation"
  def get_active_api_key do
    # Try primary key first
    case MyApp.Secrets.get_secret("API_KEY_PRIMARY") do
      nil -> 
        # Fallback to secondary during rotation
        MyApp.Secrets.get_secret("API_KEY_SECONDARY")
      key -> 
        key
    end
  end

  def health_check do
    keys = [
      MyApp.Secrets.get_secret("API_KEY_PRIMARY"),
      MyApp.Secrets.get_secret("API_KEY_SECONDARY")
    ]
    
    valid_keys = Enum.count(keys, &(&1 != nil))
    
    case valid_keys do
      0 -> {:error, "No valid API keys"}
      1 -> {:warning, "Only one API key configured"}
      _ -> {:ok, "Multiple API keys available"}
    end
  end
end
```

## Audit Logging

### Security Event Logging

```elixir
defmodule MyApp.Security.AuditLog do
  require Logger

  def log_security_event(event_type, details, context) do
    Logger.warning("Security event",
      event_type: event_type,
      details: sanitize_for_logging(details),
      user_id: Map.get(context, :user_id),
      ip_address: Map.get(context, :ip_address),
      timestamp: DateTime.utc_now(),
      session_id: Map.get(context, :session_id)
    )
    
    # Also send to security monitoring system
    send_to_security_system(event_type, details, context)
  end

  defp sanitize_for_logging(details) do
    # Remove sensitive data from logs
    Map.drop(details, [:password, :token, :api_key, :secret])
  end

  defp send_to_security_system(event_type, details, context) do
    # Send to external security monitoring
    # Implementation depends on your monitoring system
    :ok
  end
end

defmodule MyApp.Actions.AuditedAction do
  use Jido.Action

  def run(params, context) do
    # Log action start
    MyApp.Security.AuditLog.log_security_event(
      :action_started,
      %{action: __MODULE__, params: sanitize_params(params)},
      context
    )
    
    result = perform_action(params, context)
    
    # Log action completion
    MyApp.Security.AuditLog.log_security_event(
      :action_completed,
      %{action: __MODULE__, result: :success},
      context
    )
    
    result
  rescue
    exception ->
      # Log action failure
      MyApp.Security.AuditLog.log_security_event(
        :action_failed,
        %{action: __MODULE__, error: exception.message},
        context
      )
      
      reraise exception, __STACKTRACE__
  end

  defp sanitize_params(params) do
    # Remove sensitive parameters from audit logs
    Map.drop(params, [:password, :credit_card, :ssn])
  end
end
```

## Security Testing

### Security Test Patterns

```elixir
defmodule MyApp.Actions.SecurityTest do
  use ExUnit.Case

  describe "input validation security" do
    test "rejects SQL injection attempts" do
      malicious_input = "'; DROP TABLE users; --"
      
      assert {:error, error} = MyApp.Actions.ProcessInput.run(
        %{query: malicious_input},
        %{}
      )
      
      assert error.type == :validation_error
    end

    test "rejects oversized inputs" do
      large_input = String.duplicate("A", 2_000_000)  # 2MB
      
      assert {:error, error} = MyApp.Actions.ProcessInput.run(
        %{data: large_input},
        %{}
      )
      
      assert error.message =~ "too large"
    end

    test "sanitizes dangerous content" do
      dangerous_content = "<script>alert('xss')</script>"
      
      assert {:ok, result} = MyApp.Actions.SanitizeInput.run(
        %{content: dangerous_content},
        %{}
      )
      
      refute String.contains?(result.content, "<script>")
    end
  end

  describe "authorization security" do
    test "requires authentication" do
      assert {:error, error} = MyApp.Actions.AuthorizedAction.run(
        %{resource_id: "res_123", action: :read},
        %{}  # No user context
      )
      
      assert error.message =~ "Authentication required"
    end

    test "enforces role-based access" do
      user_context = %{user_id: "user_123", user_role: :user}
      
      assert {:error, error} = MyApp.Actions.AdminOnlyAction.run(
        %{operation: :delete_all},
        user_context
      )
      
      assert error.message =~ "Insufficient permissions"
    end
  end
end
```

## Best Practices

### Defense in Depth
- **Input Validation**: Validate at multiple layers
- **Output Encoding**: Encode outputs for target context
- **Principle of Least Privilege**: Grant minimal necessary permissions
- **Fail Securely**: Default to denying access

### Secret Management
- **Environment Variables**: Store secrets in environment variables
- **No Hard-coding**: Never hard-code secrets in source code
- **Rotation**: Support secret rotation without downtime
- **Logging**: Never log secrets or sensitive data

### Access Control
- **Authentication**: Verify user identity
- **Authorization**: Check permissions for each action
- **Session Management**: Secure session handling
- **Audit Logging**: Log all security-relevant events

### Resource Protection
- **Rate Limiting**: Prevent abuse and DoS attacks
- **Input Limits**: Limit input size and complexity
- **Timeout Enforcement**: Prevent resource exhaustion
- **Memory Monitoring**: Monitor and limit memory usage

## Next Steps

**→ [Testing Guide](testing.md)** - Security testing strategies  
**→ [Configuration Guide](configuration.md)** - Security configuration  
**→ [FAQ](faq.md)** - Common security questions

---
← [Configuration Guide](configuration.md) | **Next: [Testing Guide](testing.md)** →
