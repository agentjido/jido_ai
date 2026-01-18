# Phase 6 Security Review

**Date:** 2026-01-14
**Reviewer:** Security Review Agent
**Scope:** Phase 6 - Uncertainty Estimation and Calibration Gates
**Status:** ✅ PASSED with recommendations

---

## Executive Summary

Phase 6 implements confidence estimation, calibration gates, selective generation, and uncertainty quantification. The security posture is **generally strong** with proper input validation, structured error handling, and secure telemetry practices. However, several areas require attention to prevent potential security issues.

**Overall Risk Level:** 🟡 **MEDIUM**

### Key Findings Summary

- **Critical Issues:** 0
- **High Priority:** 1
- **Medium Priority:** 3
- **Low Priority:** 4
- **Informational:** 2

---

## 1. Input Validation Analysis

### ✅ 1.1 ConfidenceEstimate - Strong Validation

**File:** `/home/ducky/code/agentjido/jido_ai/lib/jido_ai/accuracy/confidence_estimate.ex`

**Strengths:**
- Proper validation of confidence scores: `validate_score/1` ensures scores are in `[0.0, 1.0]`
- Method validation ensures non-nil atom or binary values
- Type guards on all public functions prevent invalid type usage

```elixir
defp validate_score(score) when is_number(score) do
  if score >= 0.0 and score <= 1.0 do
    :ok
  else
    {:error, :invalid_score}
  end
end
```

**Status:** ✅ Secure

### ✅ 1.2 CalibrationGate - Robust Threshold Validation

**File:** `/home/ducky/code/agentjido/jido_ai/lib/jido_ai/accuracy/calibration_gate.ex`

**Strengths:**
- Validates threshold ordering: `high_threshold` must be > `low_threshold`
- Action validation against allowlist `@default_actions`
- Type checking with guards prevents pattern matching errors

```elixir
defp validate_thresholds(high, low) when is_number(high) and is_number(low) do
  if high > low do
    :ok
  else
    {:error, :invalid_thresholds}
  end
end
```

**Status:** ✅ Secure

### ⚠️ 1.3 SelectiveGeneration - Missing Upper Bounds

**File:** `/home/ducky/code/agentjido/jido_ai/lib/jido_ai/accuracy/selective_generation.ex`

**Issue:**
- `validate_reward/1` only checks `reward > 0` with no upper bound
- `validate_penalty/1` only checks `penalty >= 0` with no upper bound
- Extremely large values could lead to unexpected behavior in EV calculations

**Risk:** MEDIUM
- Attackers could set extremely high reward values to force answer decisions
- Could be used to bypass abstention logic in safety-critical scenarios

**Recommendation:**
```elixir
# Current (vulnerable)
defp validate_reward(reward) when is_number(reward) and reward > 0, do: :ok

# Recommended
defp validate_reward(reward) when is_number(reward) and reward > 0 and reward <= 1000.0, do: :ok
defp validate_reward(_), do: {:error, :invalid_reward}

defp validate_penalty(penalty) when is_number(penalty) and penalty >= 0 and penalty <= 1000.0, do: :ok
defp validate_penalty(_), do: {:error, :invalid_penalty}
```

**Status:** ⚠️ Needs remediation

### ⚠️ 1.4 UncertaintyQuantification - Regex Injection Risk

**File:** `/home/ducky/code/agentjido/jido_ai/lib/jido_ai/accuracy/uncertainty_quantification.ex`

**Issue:**
- Accepts user-provided regex patterns via `:aleatoric_patterns` and `:epistemic_patterns`
- While `validate_patterns/1` checks they're `%Regex{}`, it doesn't validate pattern complexity
- Complex regexes could cause ReDoS (Regular Expression Denial of Service)

**Risk:** MEDIUM
- Malicious users could provide catastrophic backtracking patterns
- Could cause CPU exhaustion and system hangs

**Current Mitigation:**
```elixir
defp validate_patterns(patterns) when is_list(patterns) do
  if Enum.all?(patterns, &is_valid_regex/1) do
    :ok
  else
    {:error, :invalid_patterns}
  end
end

defp is_valid_regex(%Regex{}), do: true
defp is_valid_regex(_), do: false
```

**Recommendation:**
- Add regex complexity validation (max length, no nested quantifiers)
- Consider wrapping regex operations in timeout (as done in `StaticAnalysisVerifier`)
- Document the ReDoS risk in @moduledoc

**Status:** ⚠️ Needs remediation

---

## 2. Error Handling & Information Disclosure

### ✅ 2.1 Error Messages - Generic and Safe

**Observation:**
- All error messages use generic atoms (`:invalid_score`, `:invalid_thresholds`)
- No sensitive data leaked through error messages
- No stack traces exposed in error tuples

**Example:**
```elixir
{:error, :invalid_score}
{:error, :invalid_thresholds}
{:error, :invalid_action}
```

**Status:** ✅ Secure

### ⚠️ 2.2 inspect() Usage in Error Messages

**Issue Found:**
Multiple modules use `inspect/1` in error messages within `new!/1` functions:

```elixir
# confidence_estimate.ex:127
{:error, reason} -> raise ArgumentError, "Invalid ConfidenceEstimate: #{inspect(reason)}"

# calibration_gate.ex:151
{:error, reason} -> raise ArgumentError, "Invalid CalibrationGate: #{inspect(reason)}"
```

**Risk:** LOW
- Could leak internal state if error atoms contain sensitive data
- Currently uses atoms (safe), but future changes could introduce sensitive data

**Recommendation:**
- Keep using atoms, but add a comment warning about sensitive data
- Consider a helper function that redacts sensitive fields before inspection

**Status:** ⚠️ Informational - Document best practices

### ✅ 2.3 Exception Handling - Proper Isolation

**Observation:**
- EnsembleConfidence wraps estimator calls in try/rescue (line 284-295)
- Prevents estimator failures from crashing the entire ensemble
- Returns `{:error, :invalid_estimator}` without exposing exception details

```elixir
try do
  estimator = struct!(module, config_to_map(config))
  # ...
rescue
  _ -> {:error, :invalid_estimator}
end
```

**Status:** ✅ Secure

---

## 3. Telemetry Security Analysis

### ✅ 3.1 CalibrationGate Telemetry - Safe

**File:** `/home/ducky/code/agentjido/jido_ai/lib/jido_ai/accuracy/calibration_gate.ex`

**Emitted Event:**
```elixir
:telemetry.execute(
  [:jido, :accuracy, :calibration, :route],
  %{duration: duration},
  %{
    action: result.action,
    confidence_level: result.confidence_level,
    score: result.original_score
  }
)
```

**Analysis:**
- ✅ No candidate content or queries logged
- ✅ Only numerical scores and atoms (safe)
- ✅ Metadata is minimal and non-sensitive

**Status:** ✅ Secure

### ⚠️ 3.2 ConfidenceEstimate Metadata - Potential Leak

**File:** `/home/ducky/code/agentjido/jido_ai/lib/jido_ai/accuracy/estimators/attention_confidence.ex`

**Metadata Stored:**
```elixir
metadata: %{
  aggregation: aggregation,
  token_count: length(token_probs),
  min_token_prob: Enum.min(token_probs),
  max_token_prob: Enum.max(token_probs)
}
```

**Risk:** LOW
- Token probabilities could theoretically be used to reconstruct text
- Very low practical risk (probabilities don't reveal content)
- Not currently exposed via telemetry

**Recommendation:**
- Document that metadata should never contain raw content
- Add a comment explaining the security considerations

**Status:** ⚠️ Informational - Document expectations

### ✅ 3.3 SelectiveGeneration Metadata - Safe

**Observation:**
- Metadata contains reward, penalty, and EV calculations
- All numerical values, no text content
- No PII or sensitive information

**Status:** ✅ Secure

---

## 4. Telemetry Comparison with Best Practices

### ✅ 4.1 PII Sanitization Reference

**File:** `/home/ducky/code/agentjido/jido_ai/lib/jido_ai/accuracy/self_consistency.ex`

**Existing Pattern:**
```elixir
defp sanitize_prompt_for_telemetry(prompt) when is_binary(prompt) do
  prompt
  |> String.replace(~r/\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b/, "[EMAIL]")
  |> String.replace(~r/\b\d{3}-\d{2}-\d{4}\b/, "[SSN]")
  |> String.replace(~r/\b\d{16}\b/, "[CREDIT_CARD]")
  |> truncate_prompt_for_telemetry()
end
```

**Observation:**
- Phase 6 doesn't log prompts, so PII sanitization isn't needed
- CalibrationGate only logs routing decisions (safe)
- Confidence scores and metadata are non-sensitive

**Status:** ✅ Secure - No PII exposure

---

## 5. Potential Abuse Vectors

### 🔴 5.1 Confidence Manipulation - HIGH PRIORITY

**Vulnerability:**
The calibration gate can be bypassed by manipulating confidence estimates:

```elixir
# Scenario: Attacker controls candidate metadata
candidate = %Candidate{
  content: "Malicious answer",
  metadata: %{
    logprobs: [0.0, 0.0, 0.0, 0.0]  # All perfect probabilities
  }
}

# This would yield confidence = 1.0 and bypass all gates
{:ok, estimate} = AttentionConfidence.estimate(estimator, candidate, %{})
# => score: 1.0, routes as :direct
```

**Risk:** HIGH
- If metadata is controlled by untrusted sources (e.g., external APIs)
- Could be used to force malicious content through
- Affects accuracy and safety systems

**Mitigation Required:**
```elixir
# Add metadata validation
defp extract_logprobs(%Candidate{metadata: metadata}) when is_map(metadata) do
  case Map.get(metadata, :logprobs) do
    nil -> {:error, :no_logprobs}
    [] -> {:error, :empty_logprobs}
    logprobs when is_list(logprobs) ->
      # Validate logprob bounds
      if Enum.all?(logprobs, fn lp -> is_number(lp) and lp <= 0.0 end) do
        {:ok, logprobs}
      else
        {:error, :invalid_logprobs}
      end
    _ -> {:error, :invalid_logprobs}
  end
end
```

**Recommendation:** HIGH PRIORITY - Add logprob validation

### ⚠️ 5.2 Ensemble Weight Manipulation

**Vulnerability:**
EnsembleConfidence doesn't validate that weights sum to a reasonable value:

```elixir
# Scenario: Attacker provides malicious weights
estimator = EnsembleConfidence.new!(%{
  estimators: [...],
  weights: [1000.0, 0.0001],  # Heavily biased
  combination_method: :weighted_mean
})
```

**Risk:** MEDIUM
- Could bias ensemble results toward specific estimators
- Could be used to bypass safety checks

**Current Mitigation:**
```elixir
defp validate_weights(nil, _estimator_count), do: :ok
defp validate_weights(weights, estimator_count) when is_list(weights) do
  if length(weights) == estimator_count do
    :ok
  else
    {:error, :weights_length_mismatch}
  end
end
```

**Recommendation:**
- Add weight normalization
- Add maximum weight constraint
- Consider requiring weights to sum to 1.0

```elixir
defp validate_weights(weights, estimator_count) when is_list(weights) do
  cond do
    length(weights) != estimator_count ->
      {:error, :weights_length_mismatch}
    Enum.any?(weights, fn w -> not is_number(w) or w < 0 or w > 1 end) ->
      {:error, :invalid_weight_value}
    true ->
      :ok
  end
end
```

**Status:** ⚠️ Needs remediation

### ⚠️ 5.3 Uncertainty Classification Manipulation

**Vulnerability:**
UncertaintyQuantification's pattern matching can be influenced by query crafting:

```elixir
# Scenario: Attacker wants to force aleatoric classification
"What is the best way to..."  # Matches "best" pattern
```

**Risk:** LOW
- This is intended behavior (classifying subjective questions)
- No direct security impact
- Could be abused to force specific routing paths

**Status:** ✅ Acceptable - Working as designed

---

## 6. Data Serialization Security

### ⚠️ 6.1 from_map() - Atom Conversion Risk

**Multiple Files Affected:**
- `RoutingResult.from_map/1`
- `DecisionResult.from_map/1`
- `UncertaintyResult.from_map/1`
- `ConfidenceEstimate.from_map/1`

**Issue:**
All use `String.to_existing_atom/1` for atom conversion:

```elixir
# routing_result.ex:279
defp convert_value("action", value) when is_binary(value) do
  String.to_existing_atom(value)
rescue
  ArgumentError -> value
end
```

**Risk:** LOW (MITIGATED)
- `to_existing_atom` prevents atom exhaustion attacks
- Gracefully falls back to string on error
- No denial-of-service risk

**Status:** ✅ Secure - Best practices followed

### ⚠️ 6.2 to_map() - No Data Sanitization

**Issue:**
`to_map/1` functions serialize all struct fields without sanitization:

```elixir
# confidence_estimate.ex:233
def to_map(%__MODULE__{} = estimate) do
  estimate
  |> Map.from_struct()
  |> Enum.reject(fn {k, v} -> k == :__struct__ or is_nil(v) or v == %{} end)
  |> Enum.map(fn {k, v} -> {Atom.to_string(k), v} end)
  |> Map.new()
end
```

**Risk:** LOW
- If `reasoning` or `metadata` contain sensitive data, it will be serialized
- No redaction of PII or secrets

**Recommendation:**
- Document that `to_map/1` should not be used for logging
- Add a `to_redacted_map/1` function for telemetry/serialization
- Consider adding a @sensitive tag to fields

**Status:** ⚠️ Informational - Document data sensitivity

---

## 7. Dependency Security

### ✅ 7.1 Module Loading Safety

**File:** `/home/ducky/code/agentjido/jido_ai/lib/jido_ai/accuracy/confidence_estimator.ex`

**Observation:**
```elixir
def estimator?(module) when is_atom(module) do
  Code.ensure_loaded?(module) and function_exported?(module, :estimate, 3)
end
```

**Analysis:**
- Only checks if modules are already loaded/available
- Doesn't dynamically load code
- Safe from arbitrary code execution

**Status:** ✅ Secure

### ⚠️ 7.2 EnsembleConfidence - Dynamic Module Instantiation

**File:** `/home/ducky/code/agentjido/jido_ai/lib/jido_ai/accuracy/estimators/ensemble_confidence.ex`

**Issue:**
```elixir
estimator = struct!(module, config_to_map(config))
```

**Risk:** LOW (MITIGATED)
- `module` is validated to be an atom
- `struct!` will raise if module is not a struct
- Wrapped in try/rescue for fault isolation
- No arbitrary code execution

**Status:** ✅ Secure - Properly isolated

---

## 8. Recommendations Summary

### 🔴 High Priority (Implement immediately)

1. **Validate Logprob Bounds** (Section 5.1)
   - Add validation that logprobs are ≤ 0.0
   - Prevent perfect confidence manipulation
   - File: `attention_confidence.ex`

### ⚠️ Medium Priority (Implement in next sprint)

2. **Add Upper Bounds to SelectiveGeneration** (Section 1.3)
   - Limit reward/penalty to reasonable values (e.g., 1000.0)
   - Prevent bypass through extreme values

3. **Validate Regex Complexity** (Section 1.4)
   - Add regex length limits
   - Add timeout wrappers for pattern matching
   - File: `uncertainty_quantification.ex`

4. **Add Weight Validation** (Section 5.2)
   - Normalize ensemble weights
   - Add individual weight bounds

### ℹ️ Low Priority / Informational

5. **Document Data Sensitivity** (Section 2.2, 3.2, 6.2)
   - Add @moduledoc warnings about sensitive data
   - Document telemetry expectations
   - Add comments about `inspect()` usage

6. **Add Redaction Helpers** (Section 6.2)
   - Create `to_redacted_map/1` functions
   - Use for telemetry/logging
   - Keep `to_map/1` for debugging

7. **Document Telemetry Events** (Section 3)
   - Create comprehensive telemetry documentation
   - List all emitted events and their metadata
   - Document data sensitivity

8. **Add Security Tests** (Section 5.1)
   - Test confidence manipulation attempts
   - Test extreme reward/penalty values
   - Test regex complexity limits

---

## 9. Testing Recommendations

### New Security Tests Needed

```elixir
# test/jido_ai/accuracy/phase_6_security_test.exs

defmodule Jido.AI.Accuracy.Phase6SecurityTest do
  use ExUnit.Case, async: true

  describe "ConfidenceEstimate validation" do
    test "rejects scores > 1.0" do
      assert {:error, :invalid_score} = ConfidenceEstimate.new(%{score: 1.5, method: :test})
    end

    test "rejects negative scores" do
      assert {:error, :invalid_score} = ConfidenceEstimate.new(%{score: -0.1, method: :test})
    end
  end

  describe "AttentionConfidence logprob validation" do
    test "rejects positive logprobs" do
      candidate = Candidate.new!(%{
        metadata: %{logprobs: [0.1, 0.2, 0.3]}  # Invalid: positive
      })

      assert {:error, :invalid_logprobs} =
        AttentionConfidence.estimate(estimator, candidate, %{})
    end

    test "rejects logprobs that would give perfect confidence" do
      # This should be impossible (logprob of 0.0 is extremely rare)
      # but we should handle it defensively
    end
  end

  describe "SelectiveGeneration bounds" do
    test "rejects excessive reward values" do
      assert {:error, :invalid_reward} =
        SelectiveGeneration.new(%{reward: 1_000_000.0})
    end

    test "rejects excessive penalty values" do
      assert {:error, :invalid_penalty} =
        SelectiveGeneration.new(%{penalty: 1_000_000.0})
    end
  end

  describe "EnsembleConfidence weight validation" do
    test "normalizes weights" do
      # Test that weights are normalized
    end

    test "rejects negative weights" do
      assert {:error, :invalid_weight_value} =
        EnsembleConfidence.new(%{
          estimators: [...],
          weights: [0.5, -0.5]
        })
    end
  end

  describe "UncertaintyQuantification regex safety" do
    test "limits regex complexity" do
      # Test that complex regexes are rejected
      long_pattern = ~r/#{String.duplicate("a", 10000)}/

      assert {:error, :invalid_patterns} =
        UncertaintyQuantification.new(%{
          aleatoric_patterns: [long_pattern]
        })
    end
  end

  describe "CalibrationGate telemetry" do
    test "does not leak candidate content" do
      # Attach telemetry handler
      # Verify no content in metadata
    end

    test "only emits safe data types" do
      # Verify atoms and numbers only
    end
  end
end
```

---

## 10. Conclusion

### Security Posture: ✅ STRONG (with improvements needed)

Phase 6 demonstrates good security practices:
- ✅ Proper input validation on most parameters
- ✅ Generic error messages prevent information leakage
- ✅ Safe telemetry practices (no PII logged)
- ✅ Proper exception isolation
- ⚠️ Some validation gaps need attention
- ⚠️ Documentation could be improved

### Risk Assessment

| Component | Risk Level | Status |
|-----------|-----------|--------|
| ConfidenceEstimate | 🟢 LOW | Secure |
| AttentionConfidence | 🟡 MEDIUM | Needs logprob validation |
| EnsembleConfidence | 🟡 MEDIUM | Needs weight validation |
| CalibrationGate | 🟢 LOW | Secure |
| SelectiveGeneration | 🟡 MEDIUM | Needs bounds checking |
| UncertaintyQuantification | 🟡 MEDIUM | Needs regex limits |
| Telemetry | 🟢 LOW | Secure (no PII) |

### Overall Verdict

**APPROVED with required changes before production deployment:**

1. ✅ **MUST FIX:** Add logprob validation (Section 5.1)
2. ⚠️ **SHOULD FIX:** Add reward/penalty bounds (Section 1.3)
3. ⚠️ **SHOULD FIX:** Add regex complexity limits (Section 1.4)
4. ℹ️ **NICE TO HAVE:** Improve documentation (Section 8)

### Next Steps

1. Implement high-priority fixes
2. Add security tests (Section 9)
3. Re-review after fixes
4. Document telemetry events in ops documentation
5. Consider adding security test suite to CI/CD

---

**Review Completed:** 2026-01-14
**Next Review Scheduled:** After high-priority fixes implemented
