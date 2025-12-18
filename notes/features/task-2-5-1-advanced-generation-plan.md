# Task 2.5.1: Advanced Generation Parameters - Implementation Plan

## Problem Statement

Modern LLM providers (OpenAI, Anthropic, Google, etc.) support advanced generation parameters that enable powerful capabilities like JSON mode, structured outputs, grammar-constrained generation, logit bias, and probability access. While ReqLLM (our underlying library) supports many of these parameters through its provider implementations, **Jido AI does not currently expose them to end users**.

### Current State

**What ReqLLM Supports:**
- `response_format` - JSON mode and structured output formatting (OpenAI-compatible providers)
- `logit_bias` - Token probability adjustments (Groq, OpenAI-compatible providers)
- `top_logprobs` / `logprobs` - Token probability access (OpenRouter, OpenAI-compatible)
- Provider-specific schemas via `provider_schema/0` callback
- Structured output via tool-based approach (all providers)

**What Jido AI Currently Exposes:**
- Basic sampling: `temperature`, `max_tokens`, `top_p`
- Repetition control: `frequency_penalty`, `presence_penalty`
- Tools and tool choice
- System prompts
- Streaming

**The Gap:**
Jido AI's `Jido.AI.Actions.Instructor` currently only exposes a limited subset of parameters (temperature, max_tokens, top_p, stop, mode, stream, partial). Advanced parameters supported by ReqLLM are not accessible, limiting the ability to:
- Request JSON mode responses for reliable parsing
- Access token probabilities for confidence scoring
- Apply logit bias for content control
- Use provider-specific fine-tuning parameters

## Solution Overview

Expose advanced generation parameters through Jido AI's existing action system while maintaining backward compatibility. The solution involves:

1. **Extend Instructor Action Parameters** - Add new optional parameters to `Jido.AI.Actions.Instructor`
2. **Map to ReqLLM Options** - Translate Jido AI parameters to ReqLLM's `provider_options` where appropriate
3. **Provider-Aware Parameter Handling** - Handle provider-specific parameter availability gracefully
4. **Documentation and Examples** - Provide clear guidance on using advanced parameters

### Design Principles

- **Backward Compatibility**: All new parameters are optional; existing code continues to work
- **Provider Awareness**: Parameters gracefully degrade when providers don't support them
- **Unified Interface**: Expose parameters in a provider-agnostic way where possible
- **Power User Access**: Allow direct `provider_options` passthrough for provider-specific features

## Technical Details

### Files to Modify

1. **`lib/jido_ai/actions/instructor.ex`**
   - Add new schema parameters for advanced options
   - Map parameters to ReqLLM options in `run/2`
   - Update documentation with examples

2. **Documentation to Create/Update:**
   - Update action moduledoc with advanced parameter examples
   - Add usage examples for each parameter type
   - Document provider support matrix

### Parameter Mapping Strategy

ReqLLM uses two approaches for advanced parameters:

1. **Standard Parameters** - Defined in `ReqLLM.Generation` schema (e.g., `response_format`, `seed`, `user`)
2. **Provider-Specific Parameters** - Nested under `:provider_options` keyword list

Jido AI should:
- Expose commonly-supported parameters as top-level options
- Provide `:provider_options` passthrough for provider-specific parameters
- Document which providers support which parameters

## Success Criteria

1. **JSON Mode Support**
   - Users can request JSON-formatted responses via `response_format: %{type: "json_object"}`
   - Works with OpenAI-compatible providers (OpenAI, Groq, etc.)

2. **Structured Output Support**
   - Existing Instructor integration continues to work
   - Users can specify custom response schemas via Ecto or NimbleOptions

3. **Logit Bias Support**
   - Users can provide logit bias maps to influence token generation
   - Supported on compatible providers (Groq, OpenAI)

4. **Token Probability Access**
   - Users can request token probabilities via provider-specific options
   - Works with OpenRouter (`openrouter_top_logprobs`) and compatible providers

5. **Provider Options Passthrough**
   - Users can pass arbitrary provider-specific options via `:provider_options`
   - Options are validated by ReqLLM provider schemas

6. **Backward Compatibility**
   - All existing Instructor action calls continue to work without changes
   - No breaking changes to existing APIs

## Implementation Plan

### Subtask 2.5.1.1: JSON Mode and Structured Output Formats

**Objective:** Enable users to request JSON-formatted responses and leverage structured output capabilities.

**Implementation Steps:**

1. **Add `response_format` parameter to Instructor schema:**
   ```elixir
   response_format: [
     type: :map,
     doc: "Response format specification (e.g., %{type: \"json_object\"})"
   ]
   ```

2. **Pass through to ReqLLM in Instructor.run/2:**
   ```elixir
   opts =
     [
       model: model,
       messages: convert_messages(params.prompt.messages),
       response_model: get_response_model(params_with_defaults),
       # ... existing parameters ...
     ]
     |> add_if_present(:response_format, params_with_defaults.response_format)
   ```

3. **Document JSON mode usage:**
   - Add examples showing `response_format: %{type: "json_object"}`
   - Explain provider compatibility (OpenAI, Groq, etc.)
   - Show structured output via existing `response_model` approach

4. **Testing:**
   - Test JSON mode with OpenAI provider
   - Verify structured output still works with response_model
   - Test provider compatibility error handling

**Files Modified:**
- `lib/jido_ai/actions/instructor.ex`

**Provider Support:**
- OpenAI: ✅ Full support
- Groq: ✅ Full support
- Anthropic: ⚠️ Uses tool-based approach (already supported via response_model)
- Google: ✅ Full support
- OpenRouter: ✅ Depends on underlying model

---

### Subtask 2.5.1.2: Grammar-Constrained Generation

**Objective:** Enable grammar-constrained generation where supported by providers.

**Implementation Steps:**

1. **Research provider support:**
   - Investigate which ReqLLM providers support grammar constraints
   - Check if any providers have grammar/BNF constraint parameters
   - Document findings (likely limited to local/specialized models)

2. **Determine implementation approach:**
   - If supported: Add as provider-specific option
   - If not: Document alternative approaches (JSON schema, tool definitions)

3. **Document workarounds:**
   - Explain how JSON schema provides implicit grammar constraints
   - Show how tool definitions constrain outputs
   - Note provider-specific features (e.g., Anthropic's strict mode)

**Expected Outcome:**
- Documentation of grammar constraint capabilities
- Clear guidance on using schemas for output control
- Provider-specific option support if available

**Files Modified:**
- `lib/jido_ai/actions/instructor.ex` (documentation updates)
- Potentially new examples showing schema-based constraints

**Provider Support:**
- Most providers: ⚠️ Limited (use JSON schema instead)
- Anthropic: ⚠️ Tool-based schema enforcement
- Local models (via llamacpp): Potentially supported via provider_options

---

### Subtask 2.5.1.3: Logit Bias and Token Probability Access

**Objective:** Expose logit bias control and token probability retrieval for providers that support these features.

**Implementation Steps:**

1. **Add `logit_bias` parameter:**
   ```elixir
   logit_bias: [
     type: :map,
     doc: "Map of token IDs to bias values (-100 to 100) to adjust likelihood"
   ]
   ```

2. **Add logprobs access via provider_options:**
   ```elixir
   provider_options: [
     type: {:or, [:map, {:list, :any}]},
     doc: """
     Provider-specific options (keyword list or map):
     - OpenRouter: [openrouter_top_logprobs: N]
     - OpenAI: [logprobs: true, top_logprobs: N]
     - Groq: [logit_bias: %{token_id => bias}]
     """
   ]
   ```

3. **Pass through parameters to ReqLLM:**
   ```elixir
   # In Instructor.run/2
   opts =
     [
       # ... existing options ...
     ]
     |> add_if_present(:logit_bias, params_with_defaults.logit_bias)
     |> maybe_add_provider_options(params_with_defaults.provider_options)
   ```

4. **Document usage patterns:**
   - Show how to bias specific tokens
   - Explain token probability retrieval
   - Provide examples for different providers

5. **Testing:**
   - Test logit bias with Groq provider
   - Verify token probability access with OpenRouter
   - Test provider_options passthrough

**Files Modified:**
- `lib/jido_ai/actions/instructor.ex`

**Provider Support:**
- OpenAI: ✅ logit_bias, logprobs, top_logprobs
- Groq: ✅ logit_bias
- OpenRouter: ✅ openrouter_top_logprobs (via provider_options)
- Anthropic: ❌ Not supported
- Google: ❌ Not supported

---

### Subtask 2.5.1.4: Provider-Specific Fine-Tuning Parameters

**Objective:** Expose provider-specific parameters for specialized use cases and fine-tuning.

**Implementation Steps:**

1. **Add comprehensive `provider_options` support:**
   ```elixir
   provider_options: [
     type: {:or, [:map, {:list, :any}]},
     doc: """
     Provider-specific options (keyword list or map). Examples:

     OpenAI:
       - dimensions: Embedding dimensions
       - encoding_format: "float" or "base64"

     Groq:
       - service_tier: "auto", "on_demand", "flex", "performance"
       - reasoning_effort: "none", "default", "low", "medium", "high"
       - search_settings: %{include_domains: [...], exclude_domains: [...]}
       - compound_custom: Custom Compound systems configuration

     Anthropic:
       - anthropic_top_k: Sample from top K options (1-40)
       - anthropic_version: API version string
       - anthropic_metadata: Request metadata map

     OpenRouter:
       - openrouter_top_logprobs: Number of top log probabilities
       - openrouter_models: Array of model fallbacks
       - openrouter_route: Routing preference
     """
   ]
   ```

2. **Update Instructor to preserve provider_options:**
   - Ensure provider_options are passed through to Instructor SDK
   - Map Jido.AI.Model provider-specific fields where relevant
   - Document the mapping process

3. **Create provider-specific examples:**
   - OpenAI embeddings with custom dimensions
   - Groq with reasoning_effort settings
   - Anthropic with top_k sampling
   - OpenRouter with model fallbacks

4. **Add validation helpers:**
   - Validate provider_options structure
   - Provide helpful error messages for common mistakes
   - Document schema requirements per provider

5. **Testing:**
   - Test each provider's specific options
   - Verify options are correctly passed through
   - Test validation and error handling

**Files Modified:**
- `lib/jido_ai/actions/instructor.ex`
- Create new example files showing provider-specific usage

**Provider Support Matrix:**

| Provider | Specific Parameters Available |
|----------|------------------------------|
| OpenAI | dimensions, encoding_format, max_completion_tokens (O1 models) |
| Groq | service_tier, reasoning_effort, search_settings, compound_custom, logit_bias |
| Anthropic | anthropic_top_k, anthropic_version, anthropic_metadata, stop_sequences |
| Google | (schema-based, via provider_options) |
| OpenRouter | openrouter_top_logprobs, openrouter_models, openrouter_route |

---

## Testing Strategy

### Unit Tests

1. **Parameter Schema Validation**
   - Test that new parameters are accepted
   - Verify parameter types and validation
   - Test backward compatibility (existing calls still work)

2. **Parameter Passthrough**
   - Verify parameters reach ReqLLM correctly
   - Test provider_options mapping
   - Verify optional parameters don't break when omitted

3. **Provider Compatibility**
   - Mock provider responses for each parameter type
   - Test graceful degradation for unsupported parameters
   - Verify error messages are helpful

### Integration Tests

1. **JSON Mode Testing**
   - Real API call with `response_format: %{type: "json_object"}`
   - Verify JSON parsing works correctly
   - Test with multiple providers (OpenAI, Groq)

2. **Logit Bias Testing**
   - Test token biasing with Groq
   - Verify bias affects output
   - Test invalid token ID handling

3. **Token Probability Testing**
   - Request logprobs from OpenRouter
   - Verify probability data is returned
   - Test probability threshold filtering

4. **Provider-Specific Options**
   - Test Groq reasoning_effort
   - Test Anthropic top_k sampling
   - Test OpenRouter model fallbacks

### Example Tests Structure

```elixir
# test/jido_ai/actions/instructor/advanced_parameters_test.exs

defmodule Jido.AI.Actions.Instructor.AdvancedParametersTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Actions.Instructor
  alias Jido.AI.Model
  alias Jido.AI.Prompt

  describe "JSON mode support" do
    test "accepts response_format parameter" do
      params = %{
        model: %Model{provider: :openai, model: "gpt-4", api_key: "test"},
        prompt: Prompt.new(:user, "Generate JSON"),
        response_model: MySchema,
        response_format: %{type: "json_object"}
      }

      # Should not raise
      assert {:ok, _result, _context} = Instructor.run(params, %{})
    end
  end

  describe "logit bias support" do
    test "accepts logit_bias parameter" do
      params = %{
        model: %Model{provider: :groq, model: "llama-70b", api_key: "test"},
        prompt: Prompt.new(:user, "Test"),
        response_model: MySchema,
        logit_bias: %{123 => -10, 456 => 10}
      }

      # Should not raise
      assert {:ok, _result, _context} = Instructor.run(params, %{})
    end
  end

  describe "provider_options support" do
    test "passes through provider-specific options" do
      params = %{
        model: %Model{provider: :groq, model: "llama-70b", api_key: "test"},
        prompt: Prompt.new(:user, "Test"),
        response_model: MySchema,
        provider_options: [reasoning_effort: "high", service_tier: "performance"]
      }

      # Should not raise
      assert {:ok, _result, _context} = Instructor.run(params, %{})
    end
  end
end
```

---

## Documentation Updates

### 1. Instructor Action Moduledoc

Add comprehensive section showing advanced parameter usage:

```elixir
## Advanced Parameters

### JSON Mode

Request JSON-formatted responses for reliable parsing:

    {:ok, result, _} = Instructor.run(%{
      model: %Model{provider: :openai, model: "gpt-4", api_key: key},
      prompt: Prompt.new(:user, "List 3 colors in JSON"),
      response_model: ColorList,
      response_format: %{type: "json_object"}
    })

### Logit Bias

Adjust token probabilities to influence output:

    {:ok, result, _} = Instructor.run(%{
      model: %Model{provider: :groq, model: "llama-70b", api_key: key},
      prompt: Prompt.new(:user, "Write a story"),
      response_model: Story,
      logit_bias: %{
        # Token IDs for common profanity - bias against them
        12345 => -100,
        67890 => -100
      }
    })

### Provider-Specific Options

Access advanced provider features via provider_options:

    # Groq: High reasoning effort with performance tier
    {:ok, result, _} = Instructor.run(%{
      model: %Model{provider: :groq, model: "llama-70b", api_key: key},
      prompt: Prompt.new(:user, "Solve this puzzle"),
      response_model: Solution,
      provider_options: [
        reasoning_effort: "high",
        service_tier: "performance"
      ]
    })

    # OpenRouter: Token probabilities
    {:ok, result, _} = Instructor.run(%{
      model: %Model{provider: :openrouter, model: "anthropic/claude-3", api_key: key},
      prompt: Prompt.new(:user, "Analyze sentiment"),
      response_model: Sentiment,
      provider_options: [
        openrouter_top_logprobs: 5
      ]
    })
```

### 2. Provider Support Matrix Documentation

Create a reference table showing which parameters work with which providers:

| Parameter | OpenAI | Anthropic | Groq | Google | OpenRouter |
|-----------|--------|-----------|------|--------|------------|
| response_format | ✅ | ⚠️ (via tools) | ✅ | ✅ | Varies |
| logit_bias | ✅ | ❌ | ✅ | ❌ | Varies |
| logprobs | ✅ | ❌ | ❌ | ❌ | ✅ (via provider_options) |
| provider_options | ✅ | ✅ | ✅ | ✅ | ✅ |

### 3. Usage Examples File

Create `lib/examples/advanced_generation_demo.ex` with comprehensive examples:

```elixir
defmodule Examples.AdvancedGenerationDemo do
  @moduledoc """
  Demonstrates advanced generation parameters in Jido AI.

  Shows real-world usage of:
  - JSON mode for structured responses
  - Logit bias for content control
  - Token probabilities for confidence scoring
  - Provider-specific fine-tuning options
  """

  # Examples for each parameter type...
end
```

---

## Migration Guide

For existing users upgrading to the enhanced Instructor action:

### No Breaking Changes

All existing code continues to work as-is. The new parameters are optional.

### Adoption Path

1. **Start with response_format** - Try JSON mode for more reliable parsing
2. **Explore provider_options** - Check your provider's specific features
3. **Experiment with logit_bias** - Fine-tune content filtering or style
4. **Access probabilities** - For confidence scoring and uncertainty quantification

### Common Patterns

**Before (basic usage):**
```elixir
Instructor.run(%{
  model: model,
  prompt: prompt,
  response_model: schema
})
```

**After (with advanced parameters):**
```elixir
Instructor.run(%{
  model: model,
  prompt: prompt,
  response_model: schema,
  response_format: %{type: "json_object"},  # Ensure JSON
  provider_options: [reasoning_effort: "high"]  # Provider-specific
})
```

---

## Implementation Order

### Phase 1: Foundation (Week 1)
1. Add schema parameters to Instructor action
2. Implement parameter passthrough to ReqLLM
3. Add basic unit tests

### Phase 2: Features (Week 2)
1. Implement JSON mode support (2.5.1.1)
2. Add logit bias and probability access (2.5.1.3)
3. Implement provider_options passthrough (2.5.1.4)

### Phase 3: Documentation (Week 3)
1. Update Instructor moduledoc
2. Create usage examples
3. Document provider support matrix
4. Add integration tests

### Phase 4: Refinement (Week 4)
1. Grammar constraint research and documentation (2.5.1.2)
2. Additional provider-specific examples
3. Error handling improvements
4. Performance testing

---

## Risk Assessment

### Low Risk
- Adding optional parameters (backward compatible)
- Passing through to ReqLLM (existing mechanism)
- Documentation updates

### Medium Risk
- Provider-specific validation (may need error handling improvements)
- Parameter interaction complexity (multiple advanced params together)

### Mitigation Strategies
1. Comprehensive testing with multiple providers
2. Clear documentation of parameter interactions
3. Graceful degradation for unsupported features
4. Helpful error messages for validation failures

---

## Future Enhancements

Beyond the scope of Task 2.5.1 but worth considering:

1. **Parameter Presets** - Named configurations for common use cases
2. **Provider Capability Detection** - Runtime checking of parameter support
3. **Response Metadata** - Expose more response details (finish_reason, etc.)
4. **Streaming with Advanced Parameters** - Ensure all parameters work with streaming
5. **Cost Tracking** - Expose usage and cost data from responses

---

## References

### ReqLLM Documentation
- Provider options schema: `deps/req_llm/lib/req_llm/provider/options.ex`
- Generation schema: `deps/req_llm/lib/req_llm/generation.ex`
- Provider implementations: `deps/req_llm/lib/req_llm/providers/*.ex`

### Provider-Specific Features
- **OpenAI**: https://platform.openai.com/docs/api-reference/chat/create
- **Anthropic**: https://docs.anthropic.com/en/api/messages
- **Groq**: https://console.groq.com/docs/api-reference
- **OpenRouter**: https://openrouter.ai/docs#parameters

### Existing Jido AI Code
- Current Instructor: `lib/jido_ai/actions/instructor.ex`
- Model structure: `lib/jido_ai/model.ex`
- Prompt structure: `lib/jido_ai/prompt.ex`

---

## Summary

This plan provides a comprehensive approach to exposing ReqLLM's advanced generation parameters through Jido AI's Instructor action. The implementation is backward compatible, well-tested, and thoroughly documented. Each subtask has clear objectives, implementation steps, and success criteria.

The key insight is that **ReqLLM already supports these parameters** - we just need to expose them through Jido AI's action interface and provide clear documentation for users.
