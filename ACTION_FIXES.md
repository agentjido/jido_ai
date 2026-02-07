# Jido.AI Actions SDK - Production Readiness Fixes

This document tracks issues and fixes required to make the Jido.AI Actions SDK production-ready for developers building AI agents.

## Available Actions (21 total)

| Category | Actions | Status |
|----------|---------|--------|
| **LLM** | `Chat`, `Complete`, `Embed`, `GenerateObject` | 🟡 Mostly Ready |
| **Orchestration** | `AggregateResults`, `DelegateTask`, `DiscoverCapabilities`, `SpawnChildAgent`, `StopChildAgent` | 🔴 Critical Fix Needed |
| **Planning** | `Decompose`, `Plan`, `Prioritize` | 🟡 Mostly Ready |
| **Reasoning** | `Analyze`, `Explain`, `Infer` | 🟡 Mostly Ready |
| **Streaming** | `StartStream`, `ProcessTokens`, `EndStream` | 🔴 Incomplete |
| **Tool Calling** | `CallWithTools`, `ExecuteTool`, `ListTools` | 🔴 Security Gaps |

---

## 🔴 Critical Issues

### 1. Unsafe Atom Creation in DelegateTask

**File:** `lib/jido_ai/actions/orchestration/delegate_task.ex:124`

**Problem:** `String.to_atom(decision)` on untrusted LLM output can exhaust the BEAM atom table (DoS vulnerability).

**Current Code:**
```elixir
defp parse_routing_response(text) do
  case Jason.decode(clean_text) do
    {:ok, %{"decision" => decision} = parsed} ->
      {:ok, parsed |> Map.put("decision", String.to_atom(decision))}  # UNSAFE
    ...
  end
end
```

**Fix:**
```elixir
defp parse_routing_response(text) do
  clean_text = extract_json_from_markdown(text)

  case Jason.decode(clean_text) do
    {:ok, %{"decision" => decision} = parsed} ->
      case safe_decision_atom(decision) do
        {:ok, atom} -> {:ok, Map.put(parsed, "decision", atom)}
        :error -> {:error, :invalid_routing_decision}
      end

    {:ok, _} ->
      {:error, :invalid_routing_response}

    {:error, _} ->
      {:error, :json_parse_failed}
  end
end

defp safe_decision_atom("delegate"), do: {:ok, :delegate}
defp safe_decision_atom("local"), do: {:ok, :local}
defp safe_decision_atom(_), do: :error
```

**Priority:** P0 - Fix immediately

---

### 2. Streaming Actions Are Incomplete

**Files:** 
- `lib/jido_ai/actions/streaming/start_stream.ex`
- `lib/jido_ai/actions/streaming/process_tokens.ex`
- `lib/jido_ai/actions/streaming/end_stream.ex`

**Problems:**
- No stream registry to track state by `stream_id`
- `EndStream` returns placeholder/fake data
- ETS buffer deleted before it can be retrieved
- `auto_process` parameter is accepted but ignored
- No cancellation support
- No backpressure handling

**Required Implementation:**

1. Create `Jido.AI.StreamRegistry` GenServer:
```elixir
defmodule Jido.AI.StreamRegistry do
  use GenServer

  # State per stream_id:
  # %{
  #   status: :streaming | :completed | :error | :cancelled,
  #   buffer: [binary()],
  #   usage: map(),
  #   model: string(),
  #   processor_pid: pid(),
  #   started_at: DateTime.t(),
  #   error: term() | nil
  # }

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  def register_stream(stream_id, model), do: ...
  def append_token(stream_id, token), do: ...
  def complete_stream(stream_id, usage), do: ...
  def get_stream(stream_id), do: ...
  def cancel_stream(stream_id), do: ...
end
```

2. Update `StartStream` to register with registry
3. Update `EndStream` to wait for completion and return real data
4. Add `CancelStream` action

**Alternative:** Mark streaming actions as `@experimental true` and document as unstable.

**Priority:** P0 - Either implement or mark experimental

---

### 3. Tool Calling Security Gaps

**File:** `lib/jido_ai/actions/tool_calling/call_with_tools.ex`

**Problems:**
- No argument validation against tool schemas before execution
- No per-turn tool call limits (DoS via infinite loops)
- Missing tool allowlist enforcement
- Unused opts in `execute_tools_and_continue/5` (line 231)

**Required Fixes:**

#### 3a. Add argument validation
```elixir
defp execute_single_tool(tool_call, tools) do
  name = Map.get(tool_call, :name)
  arguments = Map.get(tool_call, :arguments, %{})
  
  with {:ok, tool_module} <- find_tool(name, tools),
       :ok <- validate_tool_arguments(tool_module, arguments) do
    Tools.Executor.execute(name, arguments, %{}, tools: tools)
  end
end

defp validate_tool_arguments(tool_module, arguments) do
  case tool_module.schema() do
    schema when is_map(schema) ->
      case Zoi.validate(schema, arguments) do
        {:ok, _} -> :ok
        {:error, _} -> {:error, :invalid_tool_arguments}
      end
    _ -> :ok
  end
end
```

#### 3b. Add per-turn tool call limits
```elixir
@max_tool_calls_per_turn 10

defp execute_tools_and_continue(tool_calls, messages, model, params, context) do
  if length(tool_calls) > @max_tool_calls_per_turn do
    {:error, :too_many_tool_calls}
  else
    # ... existing logic
  end
end
```

#### 3c. Fix unused opts
```elixir
defp execute_tools_and_continue(tool_calls, messages, model, params, context) do
  tool_results = execute_all_tools(tool_calls, context)
  updated_messages = add_tool_results_to_messages(messages, tool_results)
  opts = build_opts(params)  # Now used below
  tools = get_tools(params[:tools], context)

  case ReqLLM.Generation.generate_text(model, updated_messages, Keyword.put(opts, :tools, tools)) do
    # ...
  end
end
```

**Priority:** P0 - Security critical

---

## 🟡 Moderate Issues

### 4. Inconsistent Model Schema Types

**Problem:** Actions use different Zoi types for `model` parameter:
- `Chat`, `Complete`, `GenerateObject`: `Zoi.string() |> Zoi.optional()`
- `CallWithTools`, `StartStream`: `Zoi.any() |> Zoi.optional()`

**Fix:** Standardize on `Zoi.any()` since we accept both atoms (`:fast`, `:capable`) and strings (`"anthropic:claude-haiku-4-5"`). The `BaseActionHelpers.resolve_model/2` function handles both.

```elixir
# Standard schema for model parameter
model: Zoi.any(description: "Model alias (:fast, :capable) or spec string") |> Zoi.optional()
```

**Priority:** P1

---

### 5. Duplicated Helper Code

**Problem:** Multiple actions reimplement the same functions:
- `sanitize_error_for_user/1` in Chat, Complete, Embed, GenerateObject
- `build_opts/1` in Embed, StartStream (different from BaseActionHelpers version)
- `extract_usage/1` in Planning and Reasoning actions

**Fix:** Consolidate into `BaseActionHelpers` and use consistently:

```elixir
# In each action, replace local implementations with:
alias Jido.AI.Skills.BaseActionHelpers

# Use shared functions:
BaseActionHelpers.build_opts(params)
BaseActionHelpers.extract_usage(response)
BaseActionHelpers.sanitize_error(error)
```

**Affected Files:**
- `lib/jido_ai/actions/llm/embed.ex`
- `lib/jido_ai/actions/streaming/start_stream.ex`
- `lib/jido_ai/actions/planning/*.ex`
- `lib/jido_ai/actions/reasoning/*.ex`

**Priority:** P1

---

### 6. Embed API Documentation Mismatch

**File:** `lib/jido_ai/actions/llm/embed.ex`

**Problem:** Docs say `texts` can be a string or list, but schema has two separate fields:
```elixir
# Schema has:
texts: Zoi.string() |> Zoi.optional()
texts_list: Zoi.list(Zoi.string()) |> Zoi.optional()

# But docs show:
texts: "Hello world"  # single string
texts: ["Hello", "World"]  # list - THIS WON'T WORK
```

**Fix Options:**

A) Update docs to match schema (document both `texts` and `texts_list`)
B) Change schema to accept either:
```elixir
# Use preprocessing to normalize before schema validation
def run(params, context) do
  params = normalize_texts_param(params)
  # ...
end

defp normalize_texts_param(%{texts: texts} = params) when is_list(texts) do
  params |> Map.delete(:texts) |> Map.put(:texts_list, texts)
end
defp normalize_texts_param(params), do: params
```

**Priority:** P2

---

### 7. Inconsistent Error Handling

**Problem:** Actions return errors in different formats:
- LLM actions: `{:error, "sanitized string"}`
- AggregateResults: `{:error, reason}` (raw, may leak details)
- CallWithTools: `{:ok, %{type: :error, reason: reason}}` (error hidden in success)

**Fix:** Standardize on structured errors:

```elixir
# Define in Jido.AI.Error or similar
defmodule Jido.AI.ActionError do
  defstruct [:code, :message, :details]
  
  def new(code, message, details \\ nil) do
    %__MODULE__{code: code, message: message, details: details}
  end
end

# Return consistently:
{:error, ActionError.new(:tool_execution_failed, "Tool failed to execute")}
```

**Priority:** P2

---

## 🟢 Nice-to-Have Improvements

### 8. Retry with Backoff

Add retry logic for transient provider errors (429, 5xx, timeouts).

```elixir
defmodule Jido.AI.Skills.RetryHelpers do
  def with_retry(fun, opts \\ []) do
    max_attempts = Keyword.get(opts, :max_attempts, 3)
    base_delay = Keyword.get(opts, :base_delay, 1000)
    
    do_retry(fun, 1, max_attempts, base_delay)
  end
  
  defp do_retry(fun, attempt, max, _delay) when attempt > max do
    {:error, :max_retries_exceeded}
  end
  
  defp do_retry(fun, attempt, max, delay) do
    case fun.() do
      {:ok, result} -> {:ok, result}
      {:error, reason} when reason in [:timeout, :rate_limited, :server_error] ->
        Process.sleep(delay * attempt)
        do_retry(fun, attempt + 1, max, delay)
      {:error, reason} -> {:error, reason}
    end
  end
end
```

**Priority:** P3

---

### 9. Request/Trace ID Propagation

Add trace IDs for debugging and observability:

```elixir
# In BaseActionHelpers
def build_opts(params) do
  opts = [
    max_tokens: params[:max_tokens],
    temperature: params[:temperature]
  ]
  
  opts = if params[:trace_id] do
    Keyword.put(opts, :headers, [{"x-trace-id", params[:trace_id]}])
  else
    opts
  end
  
  # ...
end
```

**Priority:** P3

---

### 10. Configurable Defaults

Allow app-level configuration for common parameters:

```elixir
# In config/config.exs
config :jido_ai, :action_defaults,
  max_tokens: 2048,
  temperature: 0.7,
  timeout: 30_000

# In BaseActionHelpers
def build_opts(params) do
  defaults = Application.get_env(:jido_ai, :action_defaults, [])
  
  [
    max_tokens: params[:max_tokens] || defaults[:max_tokens] || 1024,
    temperature: params[:temperature] || defaults[:temperature] || 0.7
  ]
  # ...
end
```

**Priority:** P3

---

## Implementation Checklist

### Phase 1: Critical Security (P0)
- [ ] Fix `String.to_atom/1` in DelegateTask
- [ ] Add tool argument validation in CallWithTools
- [ ] Add tool call limits per turn
- [ ] Fix unused opts in tool calling
- [ ] Either implement StreamRegistry or mark streaming experimental

### Phase 2: Consistency (P1)
- [ ] Standardize model schema to `Zoi.any()`
- [ ] Consolidate duplicated helpers into BaseActionHelpers
- [ ] Update all actions to use shared helpers

### Phase 3: Polish (P2)
- [ ] Fix Embed API docs/schema mismatch
- [ ] Standardize error return format
- [ ] Add ActionError struct

### Phase 4: Enhancements (P3)
- [ ] Add retry with backoff
- [ ] Add trace ID propagation
- [ ] Add configurable defaults
- [ ] Add rate limiting

---

## Testing Requirements

Each fix should include:
1. Unit tests for the specific fix
2. Integration test demonstrating correct behavior
3. Security test for P0 items (e.g., atom exhaustion, tool injection)

Example test for atom safety:
```elixir
describe "parse_routing_response/1" do
  test "rejects unknown decision values safely" do
    response = ~s({"decision": "malicious_atom_#{:rand.uniform(1000000)}"})
    assert {:error, :invalid_routing_decision} = DelegateTask.parse_routing_response(response)
  end
  
  test "accepts valid decisions" do
    assert {:ok, %{"decision" => :delegate}} = 
      DelegateTask.parse_routing_response(~s({"decision": "delegate"}))
  end
end
```
