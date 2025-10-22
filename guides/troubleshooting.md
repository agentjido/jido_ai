# Troubleshooting Guide

Common issues, solutions, and debugging strategies for Jido AI.

## Quick Diagnostics

### Health Check

```elixir
# Test basic functionality
defmodule MyApp.HealthCheck do
  def run do
    checks = [
      {"API Key Setup", &check_api_keys/0},
      {"Model Access", &check_model_access/0},
      {"Network", &check_network/0},
      {"ReqLLM Integration", &check_reqllm/0}
    ]

    Enum.each(checks, fn {name, check_fn} ->
      case check_fn.() do
        :ok ->
          IO.puts "✅ #{name}: OK"
        {:error, reason} ->
          IO.puts "❌ #{name}: #{reason}"
      end
    end)
  end

  defp check_api_keys do
    case Jido.AI.Keyring.get(:openai) do
      {:ok, _key} -> :ok
      {:error, _} -> {:error, "No API key found"}
    end
  end

  defp check_model_access do
    case Jido.AI.chat("openai:gpt-3.5-turbo", "test") do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, inspect(reason)}
    end
  end

  defp check_network do
    :ok  # Implement network check
  end

  defp check_reqllm do
    :ok  # Implement ReqLLM check
  end
end

MyApp.HealthCheck.run()
```

## Common Issues

### Authentication Errors

#### Issue: API Key Not Found

```elixir
{:error, %{type: :authentication_error, message: "API key not configured"}}
```

**Solutions:**

```elixir
# 1. Set via environment variable
export OPENAI_API_KEY="sk-..."

# 2. Set via Keyring
Jido.AI.Keyring.set(:openai, "sk-...")

# 3. Verify key is set
{:ok, key} = Jido.AI.Keyring.get(:openai)
IO.puts "Key found: #{String.slice(key, 0, 7)}..."
```

#### Issue: Invalid API Key

```elixir
{:error, %{type: :authentication_error, status: 401}}
```

**Solutions:**

```elixir
# Check key format
# OpenAI: sk-...
# Anthropic: sk-ant-...
# Groq: gsk_...

# Verify key hasn't expired
# Regenerate key in provider dashboard
```

### Model Not Found

#### Issue: Model Does Not Exist

```elixir
{:error, %{type: :model_not_found, message: "Model 'gpt-4' not found"}}
```

**Solutions:**

```elixir
# Must use provider:model format
# ❌ Wrong
Jido.AI.chat("gpt-4", prompt)

# ✅ Correct
Jido.AI.chat("openai:gpt-4", prompt)

# List available models
{:ok, models} = Jido.AI.Model.Registry.discover_models(provider: :openai)
Enum.each(models, &IO.puts/1)
```

### Rate Limiting

#### Issue: Rate Limit Exceeded

```elixir
{:error, %{type: :rate_limit, status: 429}}
```

**Solutions:**

```elixir
# 1. Implement exponential backoff
defmodule MyApp.RateLimitHandler do
  def chat_with_retry(model, prompt, retries \\ 3) do
    case Jido.AI.chat(model, prompt) do
      {:ok, response} ->
        {:ok, response}

      {:error, %{type: :rate_limit}} when retries > 0 ->
        backoff = :math.pow(2, 4 - retries) * 1000
        :timer.sleep(round(backoff))
        chat_with_retry(model, prompt, retries - 1)

      error -> error
    end
  end
end

# 2. Check rate limits
# OpenAI: https://platform.openai.com/account/limits
# Anthropic: https://console.anthropic.com/settings/limits

# 3. Upgrade tier or request increase
```

### Context Window Errors

#### Issue: Prompt Exceeds Context Window

```elixir
{:error, %ContextWindow.ContextExceededError{tokens: 150000, limit: 128000}}
```

**Solutions:**

```elixir
# 1. Enable automatic truncation
{:ok, truncated} = ContextWindow.ensure_fit(
  prompt,
  model,
  strategy: :smart_truncate
)

# 2. Use model with larger context
# GPT-4 Turbo: 128K
# Claude 3: 200K
# Gemini 1.5 Pro: 2M

# 3. Split into chunks
defmodule MyApp.ChunkProcessor do
  def process_long_document(doc, model) do
    doc
    |> chunk_document()
    |> Enum.map(fn chunk ->
      {:ok, response} = Jido.AI.chat(model, chunk)
      response.content
    end)
    |> combine_results()
  end

  defp chunk_document(doc), do: []  # Implement chunking
  defp combine_results(results), do: Enum.join(results, "\n\n")
end
```

### Timeout Errors

#### Issue: Request Timed Out

```elixir
{:error, %{type: :timeout}}
```

**Solutions:**

```elixir
# 1. Increase timeout
{:ok, response} = Jido.AI.chat(
  model,
  prompt,
  timeout: 60_000  # 60 seconds
)

# 2. Use faster model
# Instead of: "openai:gpt-4"
# Use: "groq:llama-3.1-70b" (much faster)

# 3. Reduce output length
{:ok, response} = Jido.AI.chat(
  model,
  prompt,
  max_tokens: 500  # Shorter response = faster
)

# 4. Implement async with timeout
task = Task.async(fn ->
  Jido.AI.chat(model, prompt)
end)

case Task.yield(task, 30_000) || Task.shutdown(task) do
  {:ok, result} -> result
  nil -> {:error, :timeout}
end
```

### Streaming Issues

#### Issue: Stream Not Working

```elixir
# No output or error
```

**Solutions:**

```elixir
# 1. Check provider supports streaming
# All major providers support streaming

# 2. Verify stream: true is set
{:ok, stream} = Jido.AI.chat(
  model,
  prompt,
  stream: true  # ← Required
)

# 3. Properly consume stream
stream
|> Stream.each(fn chunk ->
  IO.write(chunk.content)
end)
|> Stream.run()  # ← Don't forget to run!

# 4. Handle errors in stream
stream
|> Stream.each(fn chunk ->
  case chunk do
    %{content: content} -> IO.write(content)
    %{error: error} -> IO.puts "\nError: #{error}"
  end
end)
|> Stream.run()
```

### Provider-Specific Issues

#### OpenAI

**Issue: Model Deprecated**
```elixir
{:error, %{message: "Model gpt-4-0314 has been deprecated"}}
```

**Solution:** Use current model versions
```elixir
# Check current models
# https://platform.openai.com/docs/models

# Use: "gpt-4-turbo" or "gpt-4" (auto-updates)
```

#### Anthropic

**Issue: Context Length Error**
```elixir
{:error, %{message: "prompt is too long"}}
```

**Solution:** Claude has 200K context but check token count
```elixir
{:ok, info} = ContextWindow.check_fit(prompt, model)
IO.puts "Tokens: #{info.tokens}, Limit: #{info.limit}"
```

#### Groq

**Issue: Model Queue Full**
```elixir
{:error, %{status: 503}}
```

**Solution:** Groq free tier can queue up, retry with backoff
```elixir
# Implement retry with backoff
:timer.sleep(1000)
chat_with_retry(model, prompt, retries - 1)
```

## Feature-Specific Issues

### RAG Integration

#### Issue: Documents Not Being Used

```elixir
# Response doesn't reference documents
```

**Solutions:**

```elixir
# 1. Verify RAG support
alias Jido.AI.Features.RAG

if RAG.supports?(model) do
  IO.puts "RAG supported"
else
  IO.puts "Provider doesn't support native RAG"
  # Use alternative: Cohere, Google, or Anthropic
end

# 2. Check document format
documents = [
  %{
    content: "text...",  # Required
    title: "title"       # Recommended
  }
]

# 3. Verify documents are added to options
{:ok, opts} = RAG.build_rag_options(documents, %{}, :cohere)
IO.inspect opts  # Should contain :documents key

# 4. Explicitly request document usage in prompt
prompt = """
Based on the provided documents, answer:
#{question}
"""
```

#### Issue: Citations Not Returned

```elixir
{:ok, citations} = RAG.extract_citations(response.raw, :cohere)
# Returns: {:ok, []}
```

**Solutions:**

```elixir
# Only Cohere and Google return structured citations
# Anthropic requires manual parsing

# Check provider
case model.provider do
  :cohere -> "Has citations"
  :google -> "Has grounding metadata"
  :anthropic -> "Parse [1], [2] markers manually"
  _ -> "Not supported"
end
```

### Code Execution

#### Issue: Code Not Executing

```elixir
# Model explains code but doesn't run it
```

**Solutions:**

```elixir
# 1. Explicitly enable (security feature)
{:ok, opts} = CodeExecution.build_code_exec_options(
  %{},
  :openai,
  enable: true  # Must be true!
)

# 2. Be explicit in prompt
prompt = """
Use the code interpreter to calculate (DO NOT estimate):
#{problem}
"""

# 3. Check provider support
# Only OpenAI GPT-4/3.5 currently
if model.provider != :openai do
  IO.puts "Code execution only supported by OpenAI"
end
```

### Plugins

#### Issue: Plugin Configuration Rejected

```elixir
{:error, "Command 'bash' not allowed..."}
```

**Solutions:**

```elixir
# Security: Only whitelisted commands allowed
# Allowed: npx, node, python3, python

# ❌ Wrong
%{command: "bash"}

# ✅ Correct
%{command: "npx"}  # Use npx to run node scripts
```

#### Issue: Environment Variable Blocked

```elixir
{:error, "Environment variable 'API_KEY' contains forbidden pattern"}
```

**Solutions:**

```elixir
# Security: No secrets in environment variables

# ❌ Blocked patterns
%{env: %{
  "API_KEY" => "...",      # Contains "KEY"
  "DB_PASSWORD" => "...",  # Contains "PASSWORD"
}}

# ✅ Allowed
%{env: %{
  "NODE_ENV" => "production",
  "PORT" => "3000"
}}
```

## Debugging Strategies

### Enable Verbose Logging

```elixir
# In config/config.exs
config :logger, level: :debug

# Or at runtime
Logger.configure(level: :debug)

# Jido AI logs will show:
# - API requests
# - Parameter transformations
# - Response parsing
```

### Inspect Raw Responses

```elixir
{:ok, response} = Jido.AI.chat(model, prompt)

# Inspect normalized response
IO.inspect response, label: "Normalized"

# Inspect raw provider response
IO.inspect response.raw, label: "Raw"
```

### Test with Simple Prompts

```elixir
# Start simple
{:ok, response} = Jido.AI.chat("openai:gpt-3.5-turbo", "Say 'test'")

# If this works, issue is with your specific prompt/parameters
```

### Check Provider Status

```elixir
# OpenAI: https://status.openai.com/
# Anthropic: https://status.anthropic.com/
# Groq: https://status.groq.com/
```

### Validate Model String

```elixir
# Test model parsing
case Jido.AI.Model.from("openai:gpt-4") do
  {:ok, model} ->
    IO.inspect model
    IO.puts "Model valid"

  {:error, reason} ->
    IO.puts "Invalid model: #{inspect(reason)}"
end
```

## Performance Issues

### Slow Responses

**Solutions:**

```elixir
# 1. Use faster providers
"groq:llama-3.1-70b"        # Fastest
"together:mixtral-8x7b"     # Fast
"openai:gpt-3.5-turbo"      # Medium
"openai:gpt-4"              # Slower but better

# 2. Reduce max_tokens
max_tokens: 256  # Instead of 2000

# 3. Lower temperature
temperature: 0.3  # More deterministic = faster

# 4. Use streaming for better UX
stream: true  # User sees output immediately
```

### High Costs

**Solutions:**

```elixir
defmodule MyApp.CostControl do
  # 1. Use cheaper models for simple tasks
  def chat(prompt, complexity: :simple) do
    Jido.AI.chat("groq:llama-3.1-8b-instant", prompt)  # Free
  end

  def chat(prompt, complexity: :standard) do
    Jido.AI.chat("openai:gpt-3.5-turbo", prompt)  # Cheap
  end

  # 2. Limit max_tokens
  def chat_limited(prompt) do
    Jido.AI.chat(
      model,
      prompt,
      max_tokens: 500  # Cap output length
    )
  end

  # 3. Cache responses
  def chat_cached(prompt) do
    cache_key = :crypto.hash(:sha256, prompt) |> Base.encode16()

    case get_cache(cache_key) do
      {:ok, cached} -> {:ok, cached}
      :miss ->
        {:ok, response} = Jido.AI.chat(model, prompt)
        put_cache(cache_key, response)
        {:ok, response}
    end
  end

  defp get_cache(_key), do: :miss
  defp put_cache(_key, _value), do: :ok
end
```

## Getting Help

### Information to Include

When asking for help, include:

```elixir
# 1. Version info
IO.puts "Elixir: #{System.version()}"
IO.puts "Jido AI: #{Application.spec(:jido_ai, :vsn)}"

# 2. Model being used
IO.puts "Model: openai:gpt-4"

# 3. Error message (full)
IO.inspect error, label: "Error"

# 4. Minimal reproduction
{:ok, response} = Jido.AI.chat("openai:gpt-3.5-turbo", "test")
```

### Resources

- **GitHub Issues**: https://github.com/agentjido/jido_ai/issues
- **Documentation**: All guides in `guides/` directory
- **Examples**: https://github.com/agentjido/jido_ai/tree/main/examples

### Before Filing an Issue

1. ✅ Check this troubleshooting guide
2. ✅ Search existing GitHub issues
3. ✅ Try with a simple test case
4. ✅ Check provider status pages
5. ✅ Verify API keys are valid

## Common Error Messages

| Error | Meaning | Solution |
|-------|---------|----------|
| `API key not configured` | No API key found | Set via Keyring or environment |
| `Model 'X' not found` | Invalid model format | Use `provider:model` format |
| `Rate limit exceeded` | Too many requests | Implement retry with backoff |
| `Context window exceeded` | Prompt too long | Enable truncation or use larger model |
| `Request timed out` | Took too long | Increase timeout or use faster model |
| `Invalid JSON` | Malformed JSON response | Use `response_format: %{type: "json_object"}` |
| `Command not allowed` | Plugin security violation | Use allowed commands: npx, node, python |

## Best Practices to Avoid Issues

1. **Always use `provider:model` format**
2. **Set API keys via Keyring or environment variables**
3. **Implement retry logic for rate limits**
4. **Enable context window validation for long prompts**
5. **Use appropriate timeouts**
6. **Start with simple test cases**
7. **Monitor token usage**
8. **Check provider status before debugging**
9. **Keep dependencies updated**
10. **Read error messages carefully**

## Next Steps

- [Breaking Changes](migration/breaking-changes.md) - Version-specific issues
- [Migration Guide](migration/from-legacy-providers.md) - Upgrading code
- [Provider Matrix](providers/provider-matrix.md) - Provider-specific details
- [Feature Guides](features/) - Feature-specific troubleshooting
