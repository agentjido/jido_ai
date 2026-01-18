# Phase 6 Architecture Review

**Date**: 2026-01-14
**Reviewer**: Architecture Review
**Scope**: Phase 6 - Confidence Estimation, Calibration Gates, and Selective Generation

## Executive Summary

Phase 6 introduces a sophisticated multi-layered accuracy improvement system with three main components: confidence estimation, calibration-based routing, and selective generation using expected value calculations. The architecture demonstrates strong modular design with clear separation of concerns, good use of Elixir/OTP patterns, and extensibility. However, there are opportunities to reduce code duplication, improve integration patterns, and enhance consistency across modules.

**Overall Assessment**: **Strong** - The architecture is well-designed with minor areas for improvement.

---

## 1. Design Strengths

### 1.1 Clear Separation of Concerns

The architecture properly separates distinct concerns into focused modules:

- **Data Structures**: `ConfidenceEstimate`, `RoutingResult`, `DecisionResult`, `UncertaintyResult`
- **Behaviors**: `ConfidenceEstimator` behavior for extensibility
- **Core Logic**: `CalibrationGate`, `SelectiveGeneration`, `UncertaintyQuantification`
- **Implementations**: `AttentionConfidence`, `EnsembleConfidence`

Each module has a single, well-defined responsibility with minimal overlap.

### 1.2 Behavior-Based Extensibility

The `ConfidenceEstimator` behavior is well-designed:

```elixir
@callback estimate(struct(), Candidate.t(), context()) :: estimate_result()
@callback estimate_batch(struct(), [Candidate.t()], context()) :: ...
```

- Provides default implementation for `estimate_batch/3`
- Allows custom estimators to implement only what they need
- Clear contract with well-defined types and return values
- `estimator?/1` guard enables runtime validation

**Strength**: This pattern enables easy addition of new estimation methods (logprob-based, semantic similarity, ensemble, etc.) without modifying existing code.

### 1.3 Consistent Result Types

All result modules follow a consistent pattern:

- `new/1` and `new!/1` constructors with validation
- `to_map/1` and `from_map/1` for serialization
- Type-specific query functions (e.g., `high_confidence?/1`, `answered?/1`)
- Proper use of `@type` specifications

**Strength**: Predictable API that reduces cognitive load for users.

### 1.4 Robust Validation

All modules implement thorough validation:

```elixir
with :ok <- validate_score(score),
     :ok <- validate_method(method) do
  # ...
end
```

- Input validation on construction
- Clear error atoms (`:invalid_score`, `invalid_thresholds`)
- Use of Elixir's `with` construct for clean validation pipelines

### 1.5 Telemetry Integration

`CalibrationGate` includes built-in telemetry:

```elixir
:telemetry.execute(
  [:jido, :accuracy, :calibration, :route],
  %{duration: duration},
  %{action: result.action, confidence_level: result.confidence_level, ...}
)
```

- Structured event names
- Measurements (duration) and metadata (action, level)
- Can be disabled via configuration

**Strength**: Production-ready observability without external dependencies.

### 1.6 Expected Value Calculation

`SelectiveGeneration` implements sound decision theory:

```
EV(answer) = confidence * reward - (1 - confidence) * penalty
```

- Economically rational framework
- Domain-specific customization (medical, legal, creative)
- Clear abstention when EV ≤ 0
- Fallback to simple threshold mode

**Strength**: Theoretically grounded decision-making with practical defaults.

---

## 2. Design Weaknesses

### 2.1 Code Duplication Across Result Modules

All result modules (`ConfidenceEstimate`, `RoutingResult`, `DecisionResult`, `UncertaintyResult`) contain nearly identical helper functions:

```elixir
defp get_attr(attrs, key) when is_list(attrs) do
  Keyword.get(attrs, key)
end

defp get_attr(attrs, key) when is_map(attrs) do
  Map.get(attrs, key)
end

defp get_attr(attrs, key, default) when is_list(attrs) do
  Keyword.get(attrs, key, default)
end

defp get_attr(attrs, key, default) when is_map(attrs) do
  Map.get(attrs, key, default)
end
```

This pattern appears in **every module**.

**Impact**: ~40-50 lines of duplicated code per module × 5 modules = 200+ lines of duplication.

**Recommendation**: Extract to a shared module:

```elixir
defmodule Jido.AI.Accuracy.Helpers do
  def get_attr(attrs, key, default \\ nil)
  # ... implementation
end
```

### 2.2 Inconsistent Error Handling

While validation is good, error handling lacks consistency:

- Some functions return `{:error, atom}` (e.g., `{:error, :invalid_score}`)
- Some raise exceptions (e.g., `raise ArgumentError`)
- No standardized error structure (contrast with `Jido.AI.Error` from earlier phases)

**Example**:

```elixir
# CalibrationGate
defp validate_thresholds(high, low) when is_number(high) and is_number(low) do
  if high > low, do: :ok, else: {:error, :invalid_thresholds}
end

# But constructor raises
def new!(attrs) do
  case new(attrs) do
    {:ok, gate} -> gate
    {:error, reason} -> raise ArgumentError, "Invalid CalibrationGate: ..."
  end
end
```

**Recommendation**: Consider using the project's `Jido.AI.Error` (Splode-based) for richer error context:

```elixir
defp validate_score(score) when is_number(score) do
  if score >= 0.0 and score <= 1.0 do
    :ok
  else
    {:error, Error.exception("Invalid confidence score: #{score}. Must be in [0, 1]")}
  end
end
```

### 2.3 Missing Integration Patterns

The modules are well-designed individually but lack clear integration patterns. For example:

- How do `CalibrationGate` and `SelectiveGeneration` work together?
- When would you use `UncertaintyQuantification` vs `ConfidenceEstimate`?
- Should `EnsembleConfidence` include uncertainty quantification?

**Current State**: Each module operates independently with no orchestrator.

**Recommendation**: Document common integration patterns:

```elixir
defmodule Jido.AI.Accuracy.Pipeline do
  @doc """
  Runs a full accuracy pipeline:
  1. Estimate confidence
  2. Classify uncertainty
  3. Route through calibration gate
  4. Apply selective generation
  """
  def run(candidate, estimators, gate, sg) do
    with {:ok, estimate} <- estimate_confidence(estimators, candidate),
         {:ok, _uncertainty} <- classify_uncertainty(candidate),
         {:ok, routing} <- route(gate, candidate, estimate),
         {:ok, decision} <- decide(sg, routing.candidate, estimate) do
      {:ok, decision}
    end
  end
end
```

### 2.4 Unclear Relationship Between Modules

The relationship between confidence estimation and uncertainty quantification is unclear:

- `ConfidenceEstimate` → How confident are we in this answer?
- `UncertaintyResult` → Is this query inherently uncertain?

These are orthogonal concepts, but their interaction isn't documented.

**Recommendation**: Add documentation explaining:

1. When to use each (or both)
2. How to combine results
3. Potential conflicts (e.g., high confidence on aleatoric uncertain query)

### 2.5 Limited Pattern Validation in UncertaintyQuantification

The regex-based uncertainty detection is heuristic:

```elixir
@default_aleatoric_patterns [
  ~r/\b(best|better|worst|favorite|prefer|greatest)\b/i,
  # ...
]
```

**Issues**:

- No validation that patterns actually work
- No mechanism to tune thresholds
- Scoring uses magic numbers (`* 3.0`, `* 4.0`)

**Recommendation**:

- Add A/B testing framework for patterns
- Make scoring multipliers configurable
- Document expected accuracy/precision/recall

### 2.6 No Fallback Mechanisms

What happens when:

- `AttentionConfidence` has no logprobs? → Returns `{:error, :no_logprobs}`
- `EnsembleConfidence` has all estimators fail? → Returns `{:error, :all_estimators_failed}`
- `UncertaintyQuantification` can't classify? → Returns `:none` uncertainty

**Problem**: No graceful degradation or fallback strategies.

**Recommendation**: Implement fallback chains:

```elixir
defmodule Jido.AI.Accuracy.FallbackEstimator do
  def estimate(estimators, candidate, context) do
    # Try estimators in order, use first success
    Enum.reduce_while(estimators, {:error, :all_failed}, fn estimator, _acc ->
      case estimator.estimate(estimator, candidate, context) do
        {:ok, result} -> {:halt, {:ok, result}}
        {:error, _} -> {:cont, {:error, :all_failed}}
      end
    end)
  end
end
```

---

## 3. Modularity Assessment

### 3.1 Cohesion

**Rating**: **Excellent (9/10)**

Each module has high internal cohesion:

- `ConfidenceEstimate` → Confidence representation and query functions
- `ConfidenceEstimator` → Behavior definition only
- `AttentionConfidence` → Logprob-based estimation only
- `EnsembleConfidence` → Ensemble combination only
- `CalibrationGate` → Routing logic only
- `SelectiveGeneration` → Expected value decision making only

**No modules do multiple unrelated things.**

### 3.2 Coupling

**Rating**: **Good (7/10)**

**Low Coupling**:

- Estimators only depend on `Candidate` and `ConfidenceEstimate`
- Result modules are independent (only share `Candidate` reference)
- `UncertaintyQuantification` has no dependencies on other accuracy modules

**Areas for Improvement**:

- `CalibrationGate` couples to both `Candidate` and `ConfidenceEstimate`
- `SelectiveGeneration` couples to `Candidate`, `ConfidenceEstimate`, and `DecisionResult`
- `EnsembleConfidence` creates its own estimator structs (tight coupling to implementations)

**Recommendation**: Consider protocol-based extension:

```elixir
defprotocol Jido.AI.Accuracy.EstimatorProtocol do
  def estimate(estimator, candidate, context)
end

defimpl Jido.AI.Accuracy.EstimatorProtocol, for: Jido.AI.Accuracy.Estimators.AttentionConfidence do
  def estimate(estimator, candidate, context), do: AttentionConfidence.estimate(estimator, candidate, context)
end
```

This would allow `EnsembleConfidence` to work with any estimator implementing the protocol.

### 3.3 Reusability

**Rating**: **Excellent (9/10)**

The components are highly reusable:

- Estimators can be used independently or in ensembles
- `CalibrationGate` can be applied to any confidence estimate
- `SelectiveGeneration` works with any confidence estimate
- Result types can be serialized and stored

**Example Reuse Pattern**:

```elixir
# Use estimator independently
{:ok, estimate} = AttentionConfidence.estimate(estimator, candidate, %{})

# Apply routing
{:ok, routing} = CalibrationGate.route(gate, candidate, estimate)

# Apply selective generation
{:ok, decision} = SelectiveGeneration.answer_or_abstain(sg, candidate, estimate)
```

### 3.4 Extensibility

**Rating**: **Excellent (9/10)**

**Easy to Extend**:

1. **Add new estimator**: Implement `ConfidenceEstimator` behavior
2. **Add new routing action**: Extend `RoutingResult.action()` type
3. **Add new uncertainty type**: Extend `UncertaintyResult.uncertainty_type()` type
4. **Add new calibration strategy**: Create new module with same interface

**Example**:

```elixir
defmodule Jido.AI.Accuracy.Estimators.SemanticSimilarity do
  @behaviour Jido.AI.Accuracy.ConfidenceEstimator

  defstruct [:embedding_model]

  def estimate(estimator, candidate, context) do
    # Custom implementation
  end
end
```

---

## 4. Dependency Analysis

### 4.1 Module Dependency Graph

```
ConfidenceEstimate (struct)
  ↑
  │
ConfidenceEstimator (behavior)
  ↑
  │ implements
  ├─→ AttentionConfidence
  └─→ EnsembleConfidence ───┬─→ AttentionConfidence
                            └─→ (any estimator)

Candidate (external reference)
  ↑
  │ used by
  ├─→ ConfidenceEstimator
  ├─→ CalibrationGate ──→ RoutingResult
  └─→ SelectiveGeneration ──→ DecisionResult

UncertaintyQuantification ──→ UncertaintyResult
```

### 4.2 Circular Dependencies

**Status**: **No circular dependencies detected** ✓

The dependency graph is acyclic and well-structured.

### 4.3 External Dependencies

**Rating**: **Minimal (9/10)**

- **No external library dependencies** for core accuracy modules
- Only uses Elixir standard library (`:telemetry`, `Logger`)
- `:math.exp`, `:erlang.float_to_binary` for calculations

**Strength**: The system is lightweight and has minimal dependency risk.

---

## 5. Consistency Analysis

### 5.1 Naming Conventions

**Rating**: **Excellent (10/10)**

- Modules: `PascalCase` (e.g., `ConfidenceEstimate`, `CalibrationGate`)
- Functions: `snake_case` (e.g., `high_confidence?`, `answer_or_abstain`)
- Types: `PascalCase` with `.t()` suffix (e.g., `confidence_level()`)
- Atoms: `:snake_case` (e.g., `:with_verification`, `:aleatoric`)

**Consistent throughout.**

### 5.2 API Consistency

**Rating**: **Good (8/10)**

**Consistent Patterns**:

- All structs: `new/1`, `new!/1`, `to_map/1`, `from_map/1`
- All query functions: `?` suffix (e.g., `high_confidence?/1`, `answered?/1`)
- All validation: `with` construct returning `:ok` or `{:error, atom}`

**Inconsistencies**:

1. **Return types for batch operations**:

```elixir
# ConfidenceEstimator behavior
@callback estimate_batch(...) :: {:ok, [ConfidenceEstimate.t()]} | {:error, term()}

# But EnsembleConfidence returns same
# AttentionConfidence returns same
```

This is consistent, but the default implementation in `ConfidenceEstimator.estimate_batch/3` could be better documented.

2. **Context parameter usage**:

```elixir
# AttentionConfidence uses context for overrides
aggregation = Map.get(context, :aggregation, estimator.aggregation)

# EnsembleConfidence uses context for overrides
combination_method = Map.get(context, :combination_method, estimator.combination_method)

# But no standardization on what's in context
```

**Recommendation**: Document standard context keys or use a struct:

```elixir
defmodule Jido.AI.Accuracy.Context do
  defstruct [:domain, :aggregation, :thresholds, :metadata]
end
```

### 5.3 Type Specifications

**Rating**: **Excellent (9/10)**

All modules properly use:

- `@type` for public types
- `@spec` for public functions
- Proper use of `t()` type alias

**Minor Issue**: Some functions lack `@spec`:

```elixir
# UncertaintyQuantification
defp determine_uncertainty_type(aleatoric_score, epistemic_score, _query) do
  # No @spec (but it's private, so acceptable)
end
```

**Verdict**: Acceptable for private functions, but consider adding specs for clarity.

---

## 6. Future Extensibility

### 6.1 Adding New Estimators

**Effort**: **Low** ✓

```elixir
defmodule MyCustomEstimator do
  @behaviour Jido.AI.Accuracy.ConfidenceEstimator

  defstruct [:config]

  def estimate(estimator, candidate, context) do
    # Implementation
  end
end
```

No changes to existing code required.

### 6.2 Adding New Routing Strategies

**Effort**: **Low** ✓

Current `CalibrationGate` supports 5 actions. To add more:

1. Extend `@actions` list in `RoutingResult`
2. Extend `@type action()`
3. Add action implementation in `CalibrationGate.apply_strategy/4`
4. Add query helper (e.g., `RoutingResult.new_action?/1`)

**Estimated effort**: 1-2 hours.

### 6.3 Adding New Uncertainty Types

**Effort**: **Low** ✓

Currently supports `:aleatoric`, `:epistemic`, `:none`. To add more:

1. Extend `@uncertainty_types` in `UncertaintyResult`
2. Extend `@type uncertainty_type()`
3. Add detection logic in `UncertaintyQuantification`
4. Add action recommendation in `recommend_action/2`

**Estimated effort**: 2-3 hours.

### 6.4 Domain-Specific Customization

**Effort**: **Medium**

The system supports domain customization but requires manual configuration:

```elixir
# Medical domain
medical_sg = SelectiveGeneration.new!(%{reward: 1.0, penalty: 10.0})

# Creative domain
creative_sg = SelectiveGeneration.new!(%{reward: 1.0, penalty: 0.5})
```

**Recommendation**: Create presets:

```elixir
defmodule Jido.AI.Accuracy.Presets do
  def medical, do: SelectiveGeneration.new!(%{reward: 1.0, penalty: 10.0})
  def creative, do: SelectiveGeneration.new!(%{reward: 1.0, penalty: 0.5})
  def legal, do: SelectiveGeneration.new!(%{reward: 1.0, penalty: 20.0})
end
```

### 6.5 Machine Learning Integration

**Effort**: **Medium**

The architecture is amenable to ML integration:

1. **Learned confidence**: Replace regex/keyword patterns with learned models
2. **Adaptive thresholds**: Learn optimal thresholds per domain
3. **Calibration**: Learn mapping from raw confidence to calibrated confidence

**Example Extension**:

```elixir
defmodule Jido.AI.Accuracy.Estimators.LearnedConfidence do
  @behaviour Jido.AI.Accuracy.ConfidenceEstimator

  defstruct [:model, :preprocessor]

  def estimate(estimator, candidate, context) do
    features = extract_features(candidate)
    {:ok, score} = apply_model(estimator.model, features)
    # ...
  end
end
```

---

## 7. Performance Considerations

### 7.1 Computational Complexity

**ConfidenceEstimation**:

- `AttentionConfidence`: O(n) where n = number of tokens
- `EnsembleConfidence`: O(k) where k = number of estimators

**Routing**: O(1) - simple threshold comparisons

**SelectiveGeneration**: O(1) - arithmetic operations

**UncertaintyQuantification**: O(p*m) where p = number of patterns, m = pattern match cost

**Verdict**: Efficient for typical workloads.

### 7.2 Memory Usage

**Low memory footprint**:

- Structs are small (< 200 bytes)
- No large data structures
- Metadata can grow but is user-controlled

**Potential Issue**: `EnsembleConfidence` stores all individual estimates in metadata:

```elixir
metadata: %{
  individual_scores: Enum.map(estimates, & &1.score),
  individual_methods: Enum.map(estimates, & &1.method),
  # ...
}
```

For large ensembles, this could grow. Consider making this optional.

### 7.3 Batch Processing

**Good support**:

- `estimate_batch/3` implemented for all estimators
- Parallel processing could be added easily:

```elixir
def estimate_batch(estimator, candidates, context) do
  candidates
  |> Task.async_stream(fn candidate -> estimate(estimator, candidate, context) end)
  |> Enum.map(fn {:ok, result} -> result end)
end
```

---

## 8. Testing Assessment

Based on test files reviewed:

### 8.1 Test Coverage

**Rating**: **Excellent (9/10)**

- Comprehensive unit tests for all modules
- Edge cases covered (boundary conditions, invalid inputs)
- Property-based testing examples (EV calculations)
- Integration test patterns evident

**Example**:

```elixir
test "medical domain (high penalty)" do
  sg = SelectiveGeneration.new!(%{reward: 1.0, penalty: 10.0})
  # Even at 0.9 confidence: 0.9*1 - 0.1*10 = -0.1, should abstain
  estimate = ConfidenceEstimate.new!(%{score: 0.9, method: :test})
  assert {:ok, result} = SelectiveGeneration.answer_or_abstain(sg, candidate, estimate)
  assert result.decision == :abstain
end
```

### 8.2 Test Organization

**Rating**: **Good (8/10)**

- Clear `describe` blocks grouping related tests
- Setup functions for common test data
- Descriptive test names

**Minor Issue**: Some tests could be more focused:

```elixir
test "creates with default values" do
  assert {:ok, sg} = SelectiveGeneration.new(%{})
  assert sg.reward == 1.0
  assert sg.penalty == 1.0
  assert sg.use_ev == true
  assert sg.confidence_threshold == nil
end
```

This tests 4 assertions. Could be split into 4 focused tests.

---

## 9. Documentation Quality

### 9.1 Module Documentation

**Rating**: **Excellent (10/10)**

All modules include comprehensive `@moduledoc` with:

- Clear description of purpose
- Usage examples
- Field descriptions
- Domain-specific examples (medical, legal, creative)

**Example**:

```elixir
@moduledoc """
Implements selective generation using expected value calculation.

Selective generation decides whether to answer or abstain based on the
economic trade-off between the potential reward for a correct answer
and the penalty for a wrong answer.

## Expected Value Calculation

    EV(answer) = confidence * reward - (1 - confidence) * penalty

## Domain-Specific Costs

### Medical (Safety-Critical)
    high_penalty = SelectiveGeneration.new!(%{
      reward: 1.0,
      penalty: 10.0  # Very high cost for wrong medical advice
    })
...
"""
```

### 9.2 Function Documentation

**Rating**: **Excellent (9/10)**

All public functions have:

- Clear descriptions
- Parameter documentation
- Return value documentation
- Usage examples

**Minor Issue**: Some private functions lack documentation:

```elixir
defp get_attr(attrs, key) when is_list(attrs) do
  Keyword.get(attrs, key)
end
```

**Verdict**: Acceptable for trivial private functions.

---

## 10. Recommendations Summary

### 10.1 High Priority

1. **Extract duplicated helper functions** to reduce ~200 lines of duplication
2. **Document integration patterns** showing how modules work together
3. **Standardize error handling** using `Jido.AI.Error` or create `Jido.AI.Accuracy.Error`

### 10.2 Medium Priority

4. **Add fallback mechanisms** for graceful degradation
5. **Create preset configurations** for common domains (medical, legal, creative)
6. **Add validation for uncertainty patterns** with expected accuracy metrics

### 10.3 Low Priority

7. **Consider protocol-based extension** for looser coupling in ensembles
8. **Add optional parallelization** for batch processing
9. **Create pipeline orchestrator** for common workflows

---

## 11. Conclusion

Phase 6 demonstrates a **well-architected, extensible system** for accuracy improvement through confidence estimation, calibration-based routing, and selective generation. The design follows Elixir best practices with:

- Clear separation of concerns
- Behavior-based extensibility
- Comprehensive documentation and testing
- Minimal external dependencies
- Production-ready observability

The main areas for improvement are:

1. **Reducing code duplication** in helper functions
2. **Clarifying integration patterns** between modules
3. **Adding fallback mechanisms** for robustness

These are relatively minor issues that do not significantly impact the system's functionality or maintainability. The architecture is **production-ready** with optional enhancements for future iterations.

### Final Scores

| Criterion | Score | Notes |
|-----------|-------|-------|
| Separation of Concerns | 9/10 | Clear, focused modules |
| Modularity | 9/10 | High cohesion, low coupling |
| Reusability | 9/10 | Components highly reusable |
| Extensibility | 9/10 | Easy to add new estimators/actions |
| Consistency | 8/10 | Good, with minor API variations |
| Documentation | 10/10 | Comprehensive and clear |
| Testing | 9/10 | Thorough coverage |
| Performance | 9/10 | Efficient algorithms |
| **Overall** | **9/10** | **Strong architecture** |

---

## Appendix A: Module Reference

### Data Structures

- `Jido.AI.Accuracy.ConfidenceEstimate` - Confidence score with metadata
- `Jido.AI.Accuracy.RoutingResult` - Calibration gate routing outcome
- `Jido.AI.Accuracy.DecisionResult` - Selective generation decision
- `Jido.AI.Accuracy.UncertaintyResult` - Uncertainty classification result

### Behaviors

- `Jido.AI.Accuracy.ConfidenceEstimator` - Estimator behavior contract

### Core Logic

- `Jido.AI.Accuracy.CalibrationGate` - Confidence-based routing
- `Jido.AI.Accuracy.SelectiveGeneration` - Expected value decision making
- `Jido.AI.Accuracy.UncertaintyQuantification` - Uncertainty classification

### Implementations

- `Jido.AI.Accuracy.Estimators.AttentionConfidence` - Logprob-based estimation
- `Jido.AI.Accuracy.Estimators.EnsembleConfidence` - Ensemble combination

---

## Appendix B: Usage Patterns

### Pattern 1: Simple Confidence Estimation

```elixir
# Create estimator
estimator = AttentionConfidence.new!(%{aggregation: :product})

# Create candidate with logprobs
candidate = Candidate.new!(%{
  content: "The answer is 42",
  metadata: %{logprobs: [-0.1, -0.2, -0.05, -0.3]}
})

# Estimate
{:ok, estimate} = AttentionConfidence.estimate(estimator, candidate, %{})
```

### Pattern 2: Calibration-Based Routing

```elixir
# Create gate
gate = CalibrationGate.new!(%{
  high_threshold: 0.7,
  low_threshold: 0.4,
  medium_action: :with_verification
})

# Route candidate
{:ok, result} = CalibrationGate.route(gate, candidate, estimate)
```

### Pattern 3: Selective Generation

```elixir
# Create selective generation config
sg = SelectiveGeneration.new!(%{
  reward: 1.0,
  penalty: 5.0  # High penalty for errors
})

# Decide
{:ok, decision} = SelectiveGeneration.answer_or_abstain(sg, candidate, estimate)
```

### Pattern 4: Ensemble Estimation

```elixir
# Create ensemble
ensemble = EnsembleConfidence.new!(%{
  estimators: [
    {AttentionConfidence, [aggregation: :product]},
    {MyCustomEstimator, []}
  ],
  weights: [0.7, 0.3],
  combination_method: :weighted_mean
})

# Estimate with disagreement score
{{:ok, estimate}, disagreement} = EnsembleConfidence.estimate_with_disagreement(
  ensemble,
  candidate,
  %{}
)
```

---

**End of Review**
