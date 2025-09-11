# ReqLLM → Native Req Plugin Refactor

## Overview
Convert ReqLLM from a custom plugin system to native Req plugins by directly implementing the `attach/2` pattern and leveraging Req's step pipeline architecture.

**No Backwards Compatibility**: This is an unreleased plugin, so we can make breaking changes freely.

---

## PHASE 1 - Direct Plugin Conversion

### 1-1. Convert Anthropic Provider to Native Plugin
**File**: `lib/req_llm/providers/anthropic.ex`

Replace entire provider implementation:
```elixir
defmodule ReqLLM.Providers.Anthropic do
  @moduledoc """
  Anthropic Claude API plugin for Req.
  """

  @doc """
  Attaches the Anthropic plugin to a Req request.

  ## Request Options

    * `:model` - The Claude model to use (required)
    * `:temperature` - Controls randomness (0.0-2.0). Defaults to 0.7
    * `:max_tokens` - Maximum tokens to generate. Defaults to 1024
    * `:stream?` - Enable streaming responses. Defaults to false

  """
  def attach(request, options \\ []) do
    request
    |> Req.Request.register_options([
         :model,
         :temperature, 
         :max_tokens,
         :stream?,
         :system,
         :anthropic_version
       ])
    |> Req.Request.merge_options([
         temperature: 0.7,
         max_tokens: 1024,
         stream?: false,
         anthropic_version: "2023-06-01"
       ] ++ options)
    |> Req.Request.put_base_url("https://api.anthropic.com")
    |> Req.Request.append_request_steps([
         anthropic_auth: &auth_step/1,
         anthropic_body: &build_body_step/1
       ])
    |> Req.Request.append_response_steps([
         anthropic_parse: &parse_response_step/1
       ])
  end

  # Request steps
  defp auth_step(request) do
    api_key = System.get_env("ANTHROPIC_API_KEY") || 
              raise "ANTHROPIC_API_KEY environment variable not set"
    
    request
    |> Req.Request.put_header("x-api-key", api_key)
    |> Req.Request.put_header("anthropic-version", request.options.anthropic_version)
  end

  defp build_body_step(request) do
    body = %{
      model: request.options.model,
      messages: request.options.messages,
      max_tokens: request.options.max_tokens,
      temperature: request.options.temperature,
      stream: request.options.stream?
    }
    |> maybe_add_system(request.options.system)

    request
    |> Req.Request.put_body(Jason.encode!(body))
    |> Req.Request.put_header("content-type", "application/json")
  end

  # Response steps
  defp parse_response_step({request, response}) do
    case response.status do
      200 ->
        body = Jason.decode!(response.body)
        parsed_response = parse_anthropic_response(body, request.options.stream?)
        {request, %{response | body: parsed_response}}
      
      status ->
        error = build_error(status, response.body)
        {request, error}
    end
  end

  # Helper functions
  defp maybe_add_system(body, nil), do: body
  defp maybe_add_system(body, system), do: Map.put(body, :system, system)

  defp parse_anthropic_response(body, _stream? = false) do
    %ReqLLM.ChatCompletion{
      id: body["id"],
      model: body["model"], 
      content: extract_content(body["content"]),
      usage: extract_usage(body["usage"])
    }
  end

  defp extract_content([%{"text" => text}]), do: text
  defp extract_content(content), do: content

  defp extract_usage(%{"input_tokens" => input, "output_tokens" => output}) do
    %{input_tokens: input, output_tokens: output, total_tokens: input + output}
  end

  defp build_error(status, body) do
    %ReqLLM.Error.API{
      status: status,
      message: "Anthropic API error: #{body}"
    }
  end
end
```

### 1-2. Update Core ReqLLM API
**File**: `lib/req_llm.ex`

Simplify to work directly with Req:
```elixir
defmodule ReqLLM do
  @moduledoc """
  Composable AI interactions for Elixir, built on Req.
  """

  @doc """
  Generate text using an AI model.

  ## Examples

      iex> ReqLLM.generate_text(model: "claude-3-5-sonnet", messages: messages)
      {:ok, %ReqLLM.ChatCompletion{}}

  """
  def generate_text(opts) do
    {provider_opts, req_opts} = extract_provider_opts(opts)
    provider = determine_provider(provider_opts[:model])

    Req.new(req_opts)
    |> Req.attach(provider, provider_opts)
    |> Req.post(url: provider_path(provider), json: %{messages: provider_opts[:messages]})
    |> handle_response()
  end

  @doc """
  Stream text using an AI model.
  """
  def stream_text(opts) do
    opts
    |> Keyword.put(:stream?, true)
    |> generate_text()
  end

  # Private functions
  defp extract_provider_opts(opts) do
    provider_keys = [:model, :temperature, :max_tokens, :stream?, :messages, :system]
    {Keyword.take(opts, provider_keys), Keyword.drop(opts, provider_keys)}
  end

  defp determine_provider("claude" <> _), do: ReqLLM.Providers.Anthropic
  defp determine_provider("gpt" <> _), do: ReqLLM.Providers.OpenAI
  defp determine_provider(model), do: raise "Unknown model: #{model}"

  defp provider_path(ReqLLM.Providers.Anthropic), do: "/v1/messages"
  defp provider_path(ReqLLM.Providers.OpenAI), do: "/v1/chat/completions"

  defp handle_response({:ok, %{body: body}}), do: {:ok, body}
  defp handle_response({:error, error}), do: {:error, error}
end
```

### 1-3. Remove Legacy Architecture
**Files to Delete**:
- `lib/req_llm/plugin.ex`
- `lib/req_llm/provider.ex`
- `lib/req_llm/provider/dsl.ex`
- `lib/req_llm/provider/registry.ex`

**Files to Keep & Update**:
- `lib/req_llm/model.ex` - Simplify to just struct definition
- `lib/req_llm/error.ex` - Keep error types
- `lib/req_llm/chat_completion.ex` - Keep response struct

---

## PHASE 2 - Shared Step Extraction

### 2-1. Create Shared Authentication Step
**File**: `lib/req_llm/steps/auth.ex`
```elixir
defmodule ReqLLM.Steps.Auth do
  def bearer_token(request) do
    api_key = get_api_key(request.url.host)
    Req.Request.put_bearer_auth(request, api_key)
  end

  def anthropic_auth(request) do
    api_key = System.get_env("ANTHROPIC_API_KEY") ||
              raise "ANTHROPIC_API_KEY environment variable not set"
    
    request
    |> Req.Request.put_header("x-api-key", api_key)
    |> Req.Request.put_header("anthropic-version", "2023-06-01")
  end

  defp get_api_key("api.openai.com"), do: System.get_env("OPENAI_API_KEY")
  defp get_api_key("api.anthropic.com"), do: System.get_env("ANTHROPIC_API_KEY")
  defp get_api_key(host), do: raise "Unknown API host: #{host}"
end
```

### 2-2. Create JSON Body Step
**File**: `lib/req_llm/steps/json_body.ex`
```elixir
defmodule ReqLLM.Steps.JsonBody do
  def build_chat_completion(request) do
    body = build_body_for_provider(request)

    request
    |> Req.Request.put_body(Jason.encode!(body))
    |> Req.Request.put_header("content-type", "application/json")
  end

  defp build_body_for_provider(%{url: %{host: "api.anthropic.com"}} = request) do
    %{
      model: request.options.model,
      messages: request.options.messages,
      max_tokens: request.options.max_tokens,
      temperature: request.options.temperature,
      stream: request.options.stream?
    }
  end

  defp build_body_for_provider(%{url: %{host: "api.openai.com"}} = request) do
    %{
      model: request.options.model,
      messages: request.options.messages,
      temperature: request.options.temperature,
      stream: request.options.stream?
    }
  end
end
```

### 2-3. Create Response Parser Step
**File**: `lib/req_llm/steps/parser.ex`
```elixir
defmodule ReqLLM.Steps.Parser do  
  def parse_chat_completion({request, response}) do
    case response.status do
      200 ->
        body = Jason.decode!(response.body)
        parsed = parse_by_provider(body, request.url.host, request.options.stream?)
        {request, %{response | body: parsed}}
      
      status ->
        error = build_api_error(status, response.body)
        {request, error}
    end
  end

  defp parse_by_provider(body, "api.anthropic.com", false) do
    %ReqLLM.ChatCompletion{
      id: body["id"],
      model: body["model"],
      content: extract_anthropic_content(body["content"]),
      usage: extract_anthropic_usage(body["usage"])
    }
  end

  defp parse_by_provider(body, "api.openai.com", false) do
    choice = List.first(body["choices"])
    %ReqLLM.ChatCompletion{
      id: body["id"], 
      model: body["model"],
      content: choice["message"]["content"],
      usage: extract_openai_usage(body["usage"])
    }
  end

  # ... helper functions for extraction
end
```

### 2-4. Update Providers to Use Shared Steps
**File**: `lib/req_llm/providers/anthropic.ex`
```elixir
def attach(request, options \\ []) do
  request
  |> Req.Request.register_options([:model, :temperature, :max_tokens, :stream?, :messages])
  |> Req.Request.merge_options([temperature: 0.7, max_tokens: 1024, stream?: false] ++ options)
  |> Req.Request.put_base_url("https://api.anthropic.com")
  |> Req.Request.append_request_steps([
       anthropic_auth: &ReqLLM.Steps.Auth.anthropic_auth/1,
       build_body: &ReqLLM.Steps.JsonBody.build_chat_completion/1
     ])
  |> Req.Request.append_response_steps([
       parse_response: &ReqLLM.Steps.Parser.parse_chat_completion/1
     ])
end
```

---

## PHASE 3 - Add Remaining Providers

### 3-1. OpenAI Provider
**File**: `lib/req_llm/providers/openai.ex`
```elixir
defmodule ReqLLM.Providers.OpenAI do
  def attach(request, options \\ []) do
    request
    |> Req.Request.register_options([:model, :temperature, :stream?, :messages])
    |> Req.Request.merge_options([temperature: 0.7, stream?: false] ++ options)
    |> Req.Request.put_base_url("https://api.openai.com")
    |> Req.Request.append_request_steps([
         openai_auth: &ReqLLM.Steps.Auth.bearer_token/1,
         build_body: &ReqLLM.Steps.JsonBody.build_chat_completion/1
       ])
    |> Req.Request.append_response_steps([
         parse_response: &ReqLLM.Steps.Parser.parse_chat_completion/1
       ])
  end
end
```

### 3-2. Additional Providers
Repeat the pattern for Mistral, Cohere, etc.

---

## PHASE 4 - Polish & Documentation

### 4-1. Update Examples
**File**: `README.md`
```elixir
# Direct Req plugin usage
Req.new()
|> ReqLLM.Providers.Anthropic.attach(model: "claude-3-5-sonnet")
|> Req.post(url: "/v1/messages", json: %{messages: messages})

# High-level API
ReqLLM.generate_text(model: "claude-3-5-sonnet", messages: messages)

# Composable with other plugins
Req.new()
|> Req.attach(Req.JSON)
|> Req.attach(ReqLLM.Providers.Anthropic, model: "claude-3-5-sonnet")  
|> Req.attach(Req.Retry, max_retries: 3)
|> Req.post(json: %{messages: messages})
```

### 4-2. Generate Documentation
```bash
mix docs
```

### 4-3. Update Tests
Convert tests to use the new plugin architecture directly.

---

## Benefits Achieved

✅ **Native Req Integration**: Each provider is a proper Req plugin  
✅ **Option Validation**: `register_options/2` prevents configuration errors  
✅ **Composability**: Works seamlessly with other Req plugins  
✅ **Step Pipeline**: Clean separation of auth, body building, parsing  
✅ **Documentation**: Auto-generated docs via `@doc` annotations  
✅ **Simplicity**: Removed complex custom plugin architecture  

## Migration Complete

The refactor transforms ReqLLM from a parallel plugin system to a collection of native Req plugins, unlocking the full power of Req's ecosystem while maintaining a clean, composable API.
