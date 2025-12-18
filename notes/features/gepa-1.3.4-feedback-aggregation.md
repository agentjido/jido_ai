# GEPA Task 1.3.4: Feedback Aggregation - Planning Document

**Task:** Section 1.3.4 - Feedback Aggregation
**Status:** Planning Complete
**Date:** 2025-10-23
**Planner:** Claude Code
**Branch:** `fix/test-failures-post-reqllm-merge` (to be created: `feature/gepa-1.3.4-feedback-aggregation`)

## Table of Contents

1. [Problem Statement](#problem-statement)
2. [Solution Overview](#solution-overview)
3. [Research & Analysis](#research--analysis)
4. [Technical Architecture](#technical-architecture)
5. [Implementation Plan](#implementation-plan)
6. [Testing Strategy](#testing-strategy)
7. [Success Criteria](#success-criteria)
8. [Integration Considerations](#integration-considerations)
9. [Risk Mitigation](#risk-mitigation)

---

## Problem Statement

### Why Feedback Aggregation Is Needed

Task 1.3.4 is the critical bridge between reflection generation (Tasks 1.3.2-1.3.3) and mutation operators (Task 1.4). While individual reflections provide valuable insights, GEPA's power comes from **aggregating feedback across multiple evaluations** to identify robust, recurring patterns rather than acting on isolated observations.

**Current State:**
- ✅ Task 1.3.1: TrajectoryAnalyzer extracts failure points and success patterns
- ✅ Task 1.3.2: Reflector generates LLM-guided analysis with suggestions
- ✅ Task 1.3.3: SuggestionGenerator converts suggestions to concrete edits
- ❌ No mechanism to aggregate insights across multiple trajectories
- ❌ No pattern detection for recurring failure modes
- ❌ No deduplication of redundant suggestions
- ❌ No confidence weighting or prioritization across evaluations

### The Challenge

Consider a GEPA optimization run evaluating a prompt candidate across 10 different tasks:

1. **Individual reflections** might suggest:
   - Task 1: "Add step-by-step reasoning"
   - Task 3: "Include explicit reasoning steps"
   - Task 7: "Show intermediate calculations"
   - Task 2: "Improve tool usage documentation"
   - Task 9: "Better tool call formatting"

2. **Without aggregation:**
   - Each suggestion processed independently
   - Redundant edits (3 variations of "add reasoning steps")
   - No sense of which issues are systemic vs. task-specific
   - Equal weight to rare anomalies and recurring patterns
   - Mutation operators overwhelmed with conflicting edits

3. **With aggregation:**
   - Pattern detected: "Reasoning clarity" appears in 30% of failures
   - Deduplication: One comprehensive "add reasoning steps" suggestion
   - Prioritization: High-confidence for patterns seen multiple times
   - Weighted guidance: Focus on systemic issues first

### User Impact

**For GEPA Optimizer:**
- **Sample Efficiency**: Robust patterns emerge from multiple evaluations
- **Mutation Quality**: Mutations address real patterns, not noise
- **Convergence Speed**: Focus on high-impact improvements
- **Diversity Maintenance**: Identify when population has systemic vs. diverse issues

**For Research Goals:**
- **10-19% Improvement**: Requires acting on genuine patterns, not false signals
- **35x Fewer Rollouts**: Can't waste evaluations on noisy feedback
- **Pareto Optimization**: Need multi-objective aggregation across tasks

---

## Solution Overview

### High-Level Approach

Implement a comprehensive feedback aggregation system that:

1. **Collects** suggestions and reflections from multiple evaluations
2. **Detects patterns** in failure modes and improvement suggestions
3. **Deduplicates** redundant or semantically similar suggestions
4. **Weights** suggestions by confidence, frequency, and impact
5. **Prioritizes** guidance for mutation operators
6. **Tracks** feedback provenance and statistical significance

### Design Principles

1. **Statistical Robustness**: Distinguish genuine patterns from noise
2. **Semantic Understanding**: Group similar suggestions, not just exact matches
3. **Multi-Objective Aware**: Aggregate across different task types and objectives
4. **Provenance Tracking**: Maintain links to source trajectories and reflections
5. **Incremental Processing**: Support streaming aggregation as evaluations complete
6. **Confidence-Weighted**: Trust recurring patterns more than isolated observations

### Module Architecture

```
lib/jido/runner/gepa/
├── feedback_aggregator.ex           # Main orchestrator (1.3.4)
├── feedback_aggregation/
│   ├── collector.ex                 # Accumulate suggestions (1.3.4.1)
│   ├── pattern_detector.ex          # Identify recurring modes (1.3.4.2)
│   ├── deduplicator.ex              # Remove redundant suggestions (1.3.4.3)
│   ├── weighted_aggregator.ex       # Confidence-weighted aggregation (1.3.4.4)
│   ├── similarity_analyzer.ex       # Semantic similarity detection
│   └── aggregated_feedback.ex       # Data structures

test/jido/runner/gepa/
├── feedback_aggregator_test.exs
└── feedback_aggregation/
    ├── collector_test.exs
    ├── pattern_detector_test.exs
    ├── deduplicator_test.exs
    └── weighted_aggregator_test.exs
```

### Key Data Structures

```elixir
# Input: Multiple reflections and edit plans
ParsedReflection.t()   # from Reflector (Task 1.3.2)
EditPlan.t()           # from SuggestionGenerator (Task 1.3.3)

# Output: Aggregated feedback
AggregatedFeedback.t() # for Mutation Operators (Task 1.4)
```

---

## Research & Analysis

### GEPA Paper Insights

From the GEPA research paper and phase-05.md analysis:

**Key Requirements:**
1. **Multi-Evaluation Feedback**: Aggregate across multiple prompt evaluations
2. **Pattern Recognition**: Identify recurring failure modes vs. isolated issues
3. **Sample Efficiency**: Extract maximum insight from limited evaluations
4. **Targeted Mutations**: Guide mutations toward genuine improvements

**Research Evidence:**
- GEPA's 35x sample efficiency vs. RL comes partly from aggregating LLM feedback
- Avoiding noise: Single-evaluation feedback can be misleading
- Confidence weighting: Recurring patterns are more reliable than isolated observations
- Multi-task learning: Patterns across tasks indicate generalizable issues

### Aggregation Strategies Research

**1. Frequency-Based Aggregation**
```elixir
# Simple counting approach
"Add reasoning steps" appears in 7/10 evaluations
→ Frequency: 0.7
→ Confidence: High
```

**2. Semantic Clustering**
```elixir
# Group semantically similar suggestions
Cluster 1 "Reasoning Clarity": [
  "Add step-by-step reasoning",
  "Include intermediate steps",
  "Show work explicitly"
] → Combined suggestion with aggregate confidence
```

**3. Impact Weighting**
```elixir
# Weight by potential impact
High-impact suggestion (0.9) × Frequency (0.5) = Weighted score: 0.45
Low-impact suggestion (0.3) × Frequency (0.8) = Weighted score: 0.24
```

**4. Statistical Significance**
```elixir
# Test if pattern is statistically significant
Binomial test: Does "tool failure" appear more than random?
p-value < 0.05 → Significant pattern
p-value ≥ 0.05 → Possibly noise
```

### Deduplication Approaches

**Level 1: Exact Match**
- Identical suggestion text → Merge immediately

**Level 2: High Similarity (>0.9)**
- Nearly identical wording with minor variations
- Example: "Add examples" vs. "Include examples"
- Strategy: Keep one, aggregate metadata

**Level 3: Semantic Similarity (0.7-0.9)**
- Same intent, different wording
- Example: "Show reasoning" vs. "Explain your thinking"
- Strategy: Cluster and create combined suggestion

**Level 4: Related Concepts (0.5-0.7)**
- Overlapping but distinct suggestions
- Example: "Add constraints" vs. "Clarify requirements"
- Strategy: Keep both but note relationship

### Existing Jido Patterns

**From TrajectoryAnalyzer (Task 1.3.1):**
```elixir
# Already provides comparative analysis
ComparativeAnalysis.t() with:
- differences: [Difference.t()]
- key_factors: [String.t()]
- recommendations: [String.t()]
```

**From Reflector (Task 1.3.2):**
```elixir
ParsedReflection.t() with:
- suggestions: [Suggestion.t()]
- confidence: :high | :medium | :low
- root_causes: [String.t()]
```

**From SuggestionGenerator (Task 1.3.3):**
```elixir
EditPlan.t() with:
- edits: [PromptEdit.t()] (ranked by impact)
- high_impact_edits: integer()
- conflicts_resolved: integer()
```

---

## Technical Architecture

### Core Module: FeedbackAggregator

**Module: `Jido.Runner.GEPA.FeedbackAggregator`**

Main orchestrator coordinating the aggregation pipeline:

```elixir
defmodule Jido.Runner.GEPA.FeedbackAggregator do
  @moduledoc """
  Aggregates feedback across multiple evaluations for robust improvement guidance.

  Task 1.3.4: Feedback Aggregation

  Coordinates the four-stage aggregation pipeline:
  1. Collection: Accumulate suggestions from multiple reflections
  2. Pattern Detection: Identify recurring failure modes
  3. Deduplication: Remove redundant improvements
  4. Weighted Aggregation: Prioritize high-confidence insights

  ## Usage

      # Aggregate feedback from multiple evaluations
      reflections = [reflection1, reflection2, ...]
      edit_plans = [plan1, plan2, ...]

      {:ok, aggregated} = FeedbackAggregator.aggregate_feedback(
        reflections: reflections,
        edit_plans: edit_plans,
        options: [min_frequency: 0.2, similarity_threshold: 0.7]
      )

      # Access prioritized guidance
      aggregated.patterns           # Recurring failure modes
      aggregated.suggestions         # Deduplicated, weighted suggestions
      aggregated.high_confidence     # Most reliable improvements
  """

  alias Jido.Runner.GEPA.FeedbackAggregation.{
    Collector,
    PatternDetector,
    Deduplicator,
    WeightedAggregator,
    AggregatedFeedback
  }

  @doc """
  Aggregates feedback from multiple evaluations.

  ## Parameters

  - `opts` - Options:
    - `:reflections` - List of ParsedReflection structs
    - `:edit_plans` - List of EditPlan structs
    - `:trajectories` - Optional trajectory analysis data
    - `:min_frequency` - Minimum frequency for pattern (default: 0.2)
    - `:similarity_threshold` - Similarity threshold for deduplication (default: 0.7)
    - `:confidence_weighting` - Enable confidence weighting (default: true)

  ## Returns

  - `{:ok, AggregatedFeedback.t()}` - Aggregated, prioritized feedback
  - `{:error, reason}` - If aggregation fails
  """
  @spec aggregate_feedback(keyword()) :: {:ok, AggregatedFeedback.t()} | {:error, term()}
  def aggregate_feedback(opts \\ [])
end
```

### Subtask 1.3.4.1: Feedback Collector

**Module: `Jido.Runner.GEPA.FeedbackAggregation.Collector`**

Accumulates suggestions from multiple reflections:

```elixir
defmodule Jido.Runner.GEPA.FeedbackAggregation.Collector do
  @moduledoc """
  Collects and organizes feedback from multiple evaluation sources.

  Subtask 1.3.4.1: Create feedback collector accumulating suggestions
  from multiple reflections.
  """

  typedstruct module: FeedbackCollection do
    @moduledoc "Accumulated feedback from multiple sources"

    field(:suggestions, list(CollectedSuggestion.t()), default: [])
    field(:reflections, list(Reflector.ParsedReflection.t()), default: [])
    field(:edit_plans, list(EditPlan.t()), default: [])
    field(:total_evaluations, non_neg_integer(), default: 0)
    field(:source_metadata, map(), default: %{})
    field(:collection_timestamp, DateTime.t())
  end

  typedstruct module: CollectedSuggestion do
    @moduledoc "Suggestion with provenance tracking"

    field(:suggestion, Reflector.Suggestion.t(), enforce: true)
    field(:sources, list(String.t()), default: [])  # Evaluation IDs
    field(:frequency, float(), default: 1.0)  # How often seen
    field(:edit_impact_scores, list(float()), default: [])  # From edit plans
    field(:contexts, list(map()), default: [])  # Context from each occurrence
  end

  @doc """
  Collects suggestions from multiple reflections.
  """
  @spec collect_from_reflections([ParsedReflection.t()])
    :: {:ok, FeedbackCollection.t()} | {:error, term()}

  @doc """
  Adds edit plan information to collection.
  """
  @spec add_edit_plans(FeedbackCollection.t(), [EditPlan.t()])
    :: {:ok, FeedbackCollection.t()} | {:error, term()}

  @doc """
  Merges multiple feedback collections.
  """
  @spec merge_collections([FeedbackCollection.t()])
    :: {:ok, FeedbackCollection.t()} | {:error, term()}
end
```

### Subtask 1.3.4.2: Pattern Detector

**Module: `Jido.Runner.GEPA.FeedbackAggregation.PatternDetector`**

Identifies recurring failure modes and improvement patterns:

```elixir
defmodule Jido.Runner.GEPA.FeedbackAggregation.PatternDetector do
  @moduledoc """
  Detects recurring patterns in failure modes and suggestions.

  Subtask 1.3.4.2: Implement pattern detection identifying recurring failure modes.
  """

  typedstruct module: FailurePattern do
    @moduledoc "Detected recurring failure pattern"

    field(:id, String.t(), enforce: true)
    field(:pattern_type, atom(), enforce: true)  # :reasoning_error, :tool_failure, etc.
    field(:description, String.t(), enforce: true)
    field(:frequency, float(), enforce: true)  # 0.0-1.0
    field(:confidence, :high | :medium | :low, enforce: true)
    field(:statistical_significance, float())  # p-value if applicable
    field(:affected_evaluations, list(String.t()), default: [])
    field(:root_causes, list(String.t()), default: [])
    field(:suggested_fixes, list(String.t()), default: [])
  end

  typedstruct module: SuggestionPattern do
    @moduledoc "Detected recurring suggestion pattern"

    field(:id, String.t(), enforce: true)
    field(:category, atom(), enforce: true)  # :clarity, :constraint, :example, etc.
    field(:theme, String.t(), enforce: true)  # "Reasoning clarity"
    field(:frequency, float(), enforce: true)
    field(:suggestions, list(CollectedSuggestion.t()), default: [])
    field(:combined_rationale, String.t())
    field(:aggregate_impact, float())
  end

  @doc """
  Detects failure patterns from collected feedback.
  """
  @spec detect_failure_patterns(FeedbackCollection.t(), keyword())
    :: {:ok, [FailurePattern.t()]} | {:error, term()}

  @doc """
  Detects recurring suggestion patterns.
  """
  @spec detect_suggestion_patterns(FeedbackCollection.t(), keyword())
    :: {:ok, [SuggestionPattern.t()]} | {:error, term()}

  @doc """
  Tests statistical significance of patterns.
  """
  @spec test_significance(FailurePattern.t(), keyword())
    :: {:ok, float()} | {:error, term()}  # Returns p-value
end
```

### Subtask 1.3.4.3: Deduplicator

**Module: `Jido.Runner.GEPA.FeedbackAggregation.Deduplicator`**

Removes redundant improvements:

```elixir
defmodule Jido.Runner.GEPA.FeedbackAggregation.Deduplicator do
  @moduledoc """
  Deduplicates redundant suggestions using semantic similarity.

  Subtask 1.3.4.3: Add suggestion deduplication removing redundant improvements.
  """

  typedstruct module: SuggestionCluster do
    @moduledoc "Cluster of similar suggestions"

    field(:id, String.t(), enforce: true)
    field(:representative, Reflector.Suggestion.t(), enforce: true)
    field(:members, list(CollectedSuggestion.t()), default: [])
    field(:similarity_threshold, float(), enforce: true)
    field(:cluster_size, non_neg_integer(), default: 1)
    field(:combined_confidence, float())
    field(:aggregate_frequency, float())
  end

  @doc """
  Deduplicates suggestions by semantic similarity.

  ## Strategies

  - Level 1: Exact match (text equality)
  - Level 2: High similarity (>0.9) - merge with simple rules
  - Level 3: Semantic similarity (0.7-0.9) - cluster and combine
  - Level 4: Related (0.5-0.7) - note relationship but keep separate
  """
  @spec deduplicate(FeedbackCollection.t(), keyword())
    :: {:ok, [SuggestionCluster.t()]} | {:error, term()}

  @doc """
  Calculates similarity between two suggestions.

  Uses multiple signals:
  - Text similarity (Levenshtein, Jaccard)
  - Category matching
  - Target section overlap
  - Rationale similarity
  """
  @spec calculate_similarity(Reflector.Suggestion.t(), Reflector.Suggestion.t())
    :: float()

  @doc """
  Creates representative suggestion from cluster.
  """
  @spec create_representative(SuggestionCluster.t())
    :: {:ok, Reflector.Suggestion.t()} | {:error, term()}
end
```

### Subtask 1.3.4.4: Weighted Aggregator

**Module: `Jido.Runner.GEPA.FeedbackAggregation.WeightedAggregator`**

Prioritizes high-confidence insights:

```elixir
defmodule Jido.Runner.GEPA.FeedbackAggregation.WeightedAggregator do
  @moduledoc """
  Applies confidence weighting to aggregate feedback.

  Subtask 1.3.4.4: Support weighted aggregation prioritizing high-confidence insights.
  """

  typedstruct module: WeightedSuggestion do
    @moduledoc "Suggestion with computed confidence weights"

    field(:suggestion, Reflector.Suggestion.t(), enforce: true)
    field(:base_confidence, atom(), enforce: true)  # From original suggestion
    field(:frequency_weight, float(), enforce: true)  # Based on occurrence
    field(:impact_weight, float(), enforce: true)  # Based on impact scores
    field(:consistency_weight, float(), enforce: true)  # Based on context consistency
    field(:composite_score, float(), enforce: true)  # Final weighted score
    field(:rank, non_neg_integer())
    field(:recommendation_strength, :strong | :moderate | :weak)
  end

  @doc """
  Applies confidence weighting to deduplicated suggestions.

  ## Weighting Factors

  1. **Base Confidence**: From LLM reflection (high=1.0, medium=0.6, low=0.3)
  2. **Frequency Weight**: How often pattern appears (0.0-1.0)
  3. **Impact Weight**: Average impact score from edit plans (0.0-1.0)
  4. **Consistency Weight**: Context similarity across occurrences (0.0-1.0)

  ## Composite Score

  composite_score = (base_confidence * 0.3) +
                    (frequency_weight * 0.3) +
                    (impact_weight * 0.25) +
                    (consistency_weight * 0.15)
  """
  @spec weight_suggestions([SuggestionCluster.t()], keyword())
    :: {:ok, [WeightedSuggestion.t()]} | {:error, term()}

  @doc """
  Ranks weighted suggestions by composite score.
  """
  @spec rank_suggestions([WeightedSuggestion.t()])
    :: [WeightedSuggestion.t()]

  @doc """
  Filters suggestions below confidence threshold.
  """
  @spec filter_by_threshold([WeightedSuggestion.t()], float())
    :: [WeightedSuggestion.t()]
end
```

### Output Data Structure: AggregatedFeedback

**Module: `Jido.Runner.GEPA.FeedbackAggregation.AggregatedFeedback`**

```elixir
defmodule Jido.Runner.GEPA.FeedbackAggregation.AggregatedFeedback do
  @moduledoc """
  Complete aggregated feedback ready for mutation operators.

  Output of Task 1.3.4, input to Task 1.4 (Mutation Operators).
  """

  use TypedStruct

  typedstruct do
    field(:id, String.t(), enforce: true)

    # Core aggregated data
    field(:patterns, list(PatternDetector.FailurePattern.t()), default: [])
    field(:suggestions, list(WeightedSuggestion.t()), default: [])
    field(:high_confidence, list(WeightedSuggestion.t()), default: [])
    field(:medium_confidence, list(WeightedSuggestion.t()), default: [])
    field(:low_confidence, list(WeightedSuggestion.t()), default: [])

    # Statistical summary
    field(:total_evaluations, non_neg_integer(), enforce: true)
    field(:total_suggestions, non_neg_integer(), default: 0)
    field(:deduplicated_count, non_neg_integer(), default: 0)
    field(:significant_patterns, non_neg_integer(), default: 0)

    # Provenance
    field(:source_reflections, list(String.t()), default: [])
    field(:source_edit_plans, list(String.t()), default: [])
    field(:aggregation_timestamp, DateTime.t())

    # Configuration used
    field(:config, map(), default: %{})
    field(:metadata, map(), default: %{})
  end

  @doc """
  Creates aggregated feedback from pipeline outputs.
  """
  @spec from_pipeline(
    patterns: [FailurePattern.t()],
    suggestions: [WeightedSuggestion.t()],
    collection: FeedbackCollection.t(),
    config: keyword()
  ) :: t()

  @doc """
  Gets top N suggestions by confidence.
  """
  @spec top_suggestions(t(), pos_integer()) :: [WeightedSuggestion.t()]

  @doc """
  Filters suggestions by category.
  """
  @spec suggestions_by_category(t(), atom()) :: [WeightedSuggestion.t()]

  @doc """
  Summarizes aggregated feedback for logging/debugging.
  """
  @spec summarize(t()) :: String.t()
end
```

---

## Implementation Plan

### Phase 1: Core Collection (Subtask 1.3.4.1)

**Goal:** Accumulate suggestions from multiple reflections with provenance tracking.

#### Step 1.1: Create Collector Module and Data Structures

**File:** `lib/jido/runner/gepa/feedback_aggregation/collector.ex`

**Implementation Tasks:**
1. Define `FeedbackCollection` and `CollectedSuggestion` TypedStructs
2. Implement `collect_from_reflections/1` to extract suggestions
3. Implement provenance tracking (source IDs, contexts)
4. Add frequency counting for repeated suggestions

**Tests:**
- Collect from single reflection
- Collect from multiple reflections
- Track provenance correctly
- Count suggestion frequencies
- Handle empty/nil inputs gracefully

**Deliverables:**
- ✅ Collector module with complete TypedStructs
- ✅ Basic collection functionality
- ✅ Comprehensive unit tests
- ✅ Module documentation

---

#### Step 1.2: Add Edit Plan Integration

**Implementation Tasks:**
1. Implement `add_edit_plans/2` to augment collection with impact data
2. Link suggestions to their corresponding edit plans
3. Extract and store impact scores from edits
4. Maintain bidirectional references

**Tests:**
- Add edit plans to collection
- Correctly map suggestions to edit impacts
- Handle missing/partial edit plan data
- Validate impact score extraction

**Deliverables:**
- ✅ Edit plan integration
- ✅ Impact score tracking
- ✅ Unit tests
- ✅ Integration tests with SuggestionGenerator

---

#### Step 1.3: Implement Collection Merging

**Implementation Tasks:**
1. Implement `merge_collections/1` for incremental aggregation
2. Handle duplicate suggestions across collections
3. Aggregate frequency and provenance data
4. Support streaming/online aggregation

**Tests:**
- Merge two collections
- Merge multiple collections
- Handle overlapping suggestions
- Preserve all provenance data
- Test large collection merging performance

**Deliverables:**
- ✅ Collection merging functionality
- ✅ Incremental aggregation support
- ✅ Performance tests
- ✅ Documentation

---

### Phase 2: Pattern Detection (Subtask 1.3.4.2)

**Goal:** Identify recurring failure modes and suggestion patterns.

#### Step 2.1: Implement Failure Pattern Detection

**File:** `lib/jido/runner/gepa/feedback_aggregation/pattern_detector.ex`

**Implementation Tasks:**
1. Define `FailurePattern` and `SuggestionPattern` TypedStructs
2. Implement `detect_failure_patterns/2`
3. Extract root causes from reflection data
4. Calculate pattern frequencies across evaluations
5. Categorize failure types (reasoning, tool, state, etc.)

**Tests:**
- Detect single recurring failure pattern
- Detect multiple patterns
- Calculate pattern frequencies correctly
- Categorize failure types accurately
- Handle edge cases (all unique failures, all same failure)

**Deliverables:**
- ✅ Failure pattern detection
- ✅ Pattern categorization
- ✅ Frequency calculation
- ✅ Unit tests

---

#### Step 2.2: Implement Suggestion Pattern Detection

**Implementation Tasks:**
1. Implement `detect_suggestion_patterns/2`
2. Group suggestions by category and theme
3. Identify recurring suggestion types
4. Compute aggregate impact for patterns
5. Generate combined rationales

**Tests:**
- Detect recurring suggestion themes
- Group by category correctly
- Calculate aggregate impact
- Generate meaningful combined rationales
- Handle diverse suggestion sets

**Deliverables:**
- ✅ Suggestion pattern detection
- ✅ Theme identification
- ✅ Impact aggregation
- ✅ Unit tests

---

#### Step 2.3: Add Statistical Significance Testing

**Implementation Tasks:**
1. Implement `test_significance/2` using binomial test
2. Calculate p-values for pattern occurrence
3. Mark patterns as significant or likely noise
4. Document statistical assumptions and limitations

**Tests:**
- Test significance of common patterns (low p-value)
- Test significance of rare patterns (high p-value)
- Validate binomial test implementation
- Edge cases (single occurrence, all occurrences)

**Deliverables:**
- ✅ Statistical significance testing
- ✅ P-value calculation
- ✅ Clear significance thresholds
- ✅ Unit tests
- ✅ Statistical methodology documentation

---

### Phase 3: Deduplication (Subtask 1.3.4.3)

**Goal:** Remove redundant improvements through semantic similarity.

#### Step 3.1: Implement Similarity Analysis

**File:** `lib/jido/runner/gepa/feedback_aggregation/deduplicator.ex`

**Implementation Tasks:**
1. Define `SuggestionCluster` TypedStruct
2. Implement `calculate_similarity/2` with multiple signals:
   - Text similarity (Levenshtein distance, Jaccard similarity)
   - Category matching
   - Target section overlap
   - Rationale similarity
3. Combine similarity signals into composite score
4. Handle edge cases (empty text, nil fields)

**Tests:**
- Calculate similarity for identical suggestions (1.0)
- Calculate similarity for very similar suggestions (>0.9)
- Calculate similarity for related suggestions (0.5-0.7)
- Calculate similarity for unrelated suggestions (<0.3)
- Test each similarity signal independently
- Test composite scoring

**Deliverables:**
- ✅ Similarity calculation
- ✅ Multi-signal similarity detection
- ✅ Comprehensive unit tests
- ✅ Similarity algorithm documentation

---

#### Step 3.2: Implement Clustering and Deduplication

**Implementation Tasks:**
1. Implement `deduplicate/2` with hierarchical approach:
   - Level 1: Exact matching
   - Level 2: High similarity (>0.9) merge
   - Level 3: Semantic clustering (0.7-0.9)
   - Level 4: Relationship noting (0.5-0.7)
2. Group suggestions into clusters
3. Track cluster membership and relationships
4. Support configurable similarity thresholds

**Tests:**
- Deduplicate exact matches
- Deduplicate high similarity matches
- Cluster semantically similar suggestions
- Note related but distinct suggestions
- Test with various similarity thresholds
- Handle large suggestion sets (100+ suggestions)

**Deliverables:**
- ✅ Hierarchical deduplication
- ✅ Clustering algorithm
- ✅ Unit tests
- ✅ Performance tests

---

#### Step 3.3: Create Representative Suggestions

**Implementation Tasks:**
1. Implement `create_representative/1`
2. Select best suggestion from cluster as representative
3. Combine metadata from all cluster members
4. Preserve provenance from all sources
5. Aggregate frequency and impact data

**Tests:**
- Create representative from single-member cluster
- Create representative from multi-member cluster
- Verify metadata aggregation
- Verify provenance preservation
- Test representative selection criteria

**Deliverables:**
- ✅ Representative creation
- ✅ Metadata aggregation
- ✅ Unit tests

---

### Phase 4: Weighted Aggregation (Subtask 1.3.4.4)

**Goal:** Prioritize high-confidence insights through confidence weighting.

#### Step 4.1: Implement Confidence Weighting

**File:** `lib/jido/runner/gepa/feedback_aggregation/weighted_aggregator.ex`

**Implementation Tasks:**
1. Define `WeightedSuggestion` TypedStruct
2. Implement `weight_suggestions/2` with composite scoring:
   - Base confidence weight (30%): From LLM reflection
   - Frequency weight (30%): How often pattern appears
   - Impact weight (25%): Average impact from edit plans
   - Consistency weight (15%): Context similarity
3. Calculate composite scores
4. Support configurable weight distribution

**Tests:**
- Calculate weights for high-confidence, high-frequency suggestion
- Calculate weights for low-confidence, low-frequency suggestion
- Test each weighting component independently
- Verify composite score calculation
- Test with various weight configurations
- Validate score ranges (0.0-1.0)

**Deliverables:**
- ✅ Confidence weighting implementation
- ✅ Composite scoring
- ✅ Configurable weights
- ✅ Comprehensive unit tests
- ✅ Weighting methodology documentation

---

#### Step 4.2: Implement Ranking and Filtering

**Implementation Tasks:**
1. Implement `rank_suggestions/1` to order by composite score
2. Implement `filter_by_threshold/2` to remove low-confidence suggestions
3. Add recommendation strength classification (strong/moderate/weak)
4. Support top-N selection

**Tests:**
- Rank suggestions correctly by score
- Filter by various thresholds
- Classify recommendation strength
- Select top N suggestions
- Handle ties in ranking

**Deliverables:**
- ✅ Ranking algorithm
- ✅ Threshold filtering
- ✅ Strength classification
- ✅ Unit tests

---

### Phase 5: Integration and Main Orchestrator

**Goal:** Coordinate complete aggregation pipeline.

#### Step 5.1: Implement Main FeedbackAggregator

**File:** `lib/jido/runner/gepa/feedback_aggregator.ex`

**Implementation Tasks:**
1. Implement `aggregate_feedback/1` orchestrating full pipeline:
   - Collect suggestions (Collector)
   - Detect patterns (PatternDetector)
   - Deduplicate (Deduplicator)
   - Weight and rank (WeightedAggregator)
2. Build `AggregatedFeedback` output
3. Add configuration validation
4. Implement logging and instrumentation
5. Handle pipeline errors gracefully

**Tests:**
- End-to-end aggregation with multiple reflections
- Test each pipeline stage integration
- Validate output structure
- Test error propagation
- Test with various configurations
- Performance test with large datasets

**Deliverables:**
- ✅ Main orchestrator module
- ✅ Pipeline coordination
- ✅ Configuration management
- ✅ Integration tests
- ✅ Performance benchmarks

---

#### Step 5.2: Create AggregatedFeedback Output Structure

**File:** `lib/jido/runner/gepa/feedback_aggregation/aggregated_feedback.ex`

**Implementation Tasks:**
1. Define complete `AggregatedFeedback` TypedStruct
2. Implement `from_pipeline/1` constructor
3. Implement convenience functions (top_suggestions, suggestions_by_category)
4. Implement `summarize/1` for logging
5. Add validation and integrity checks

**Tests:**
- Create from pipeline outputs
- Test convenience functions
- Verify summarization
- Test validation rules
- Ensure all required fields populated

**Deliverables:**
- ✅ AggregatedFeedback structure
- ✅ Constructor and utilities
- ✅ Validation logic
- ✅ Unit tests
- ✅ Complete documentation

---

#### Step 5.3: Integration with Task 1.4 (Mutation Operators)

**Implementation Tasks:**
1. Document integration points with mutation system
2. Create example usage for mutation operators
3. Add conversion utilities if needed
4. Validate output format matches Task 1.4 expectations

**Tests:**
- Mock integration with mutation operators
- Test data format compatibility
- End-to-end workflow simulation

**Deliverables:**
- ✅ Integration documentation
- ✅ Example usage code
- ✅ Integration tests
- ✅ API compatibility verification

---

### Phase 6: Testing and Documentation

#### Step 6.1: Comprehensive Testing

**Test Files:**
- `test/jido/runner/gepa/feedback_aggregator_test.exs`
- `test/jido/runner/gepa/feedback_aggregation/collector_test.exs`
- `test/jido/runner/gepa/feedback_aggregation/pattern_detector_test.exs`
- `test/jido/runner/gepa/feedback_aggregation/deduplicator_test.exs`
- `test/jido/runner/gepa/feedback_aggregation/weighted_aggregator_test.exs`

**Test Coverage Goals:**
- Unit tests: >95% coverage
- Integration tests: All major workflows
- Performance tests: Large-scale aggregation (1000+ suggestions)
- Edge cases: Empty inputs, single suggestion, all duplicates

**Deliverables:**
- ✅ Complete unit test suite
- ✅ Integration tests
- ✅ Performance benchmarks
- ✅ Edge case coverage

---

#### Step 6.2: Documentation

**Documentation Tasks:**
1. Module documentation (complete @moduledoc for each module)
2. Function documentation (detailed @doc for public functions)
3. Usage examples in module docs
4. Integration guide for mutation operators
5. Algorithm documentation (similarity, weighting, statistical tests)

**Deliverables:**
- ✅ Complete module documentation
- ✅ Function documentation
- ✅ Usage examples
- ✅ Integration guide
- ✅ Algorithm documentation

---

## Testing Strategy

### Unit Testing

**Per Module:**

1. **Collector Tests** (`collector_test.exs`)
   - Collection from single/multiple reflections
   - Edit plan integration
   - Collection merging
   - Provenance tracking
   - Frequency counting

2. **Pattern Detector Tests** (`pattern_detector_test.exs`)
   - Failure pattern detection
   - Suggestion pattern detection
   - Statistical significance testing
   - Frequency calculation
   - Pattern categorization

3. **Deduplicator Tests** (`deduplicator_test.exs`)
   - Similarity calculation (all signals)
   - Exact match deduplication
   - High similarity merging
   - Semantic clustering
   - Representative creation

4. **Weighted Aggregator Tests** (`weighted_aggregator_test.exs`)
   - Weight calculation (all components)
   - Composite scoring
   - Ranking algorithm
   - Threshold filtering
   - Strength classification

5. **Main Aggregator Tests** (`feedback_aggregator_test.exs`)
   - End-to-end aggregation
   - Pipeline coordination
   - Configuration handling
   - Error propagation
   - Output validation

### Integration Testing

**Test Scenarios:**

1. **Small Dataset** (10 reflections, 30 suggestions)
   - Verify correct aggregation
   - Check pattern detection
   - Validate deduplication
   - Test weighting

2. **Large Dataset** (100 reflections, 300 suggestions)
   - Performance benchmarks
   - Memory usage
   - Scalability verification

3. **Edge Cases**
   - Empty input
   - Single reflection
   - All identical suggestions
   - No patterns detected
   - All suggestions unique

4. **Real-World Simulation**
   - Use actual reflection/edit plan data from Tasks 1.3.2/1.3.3
   - Verify integration with existing modules
   - End-to-end workflow test

### Property-Based Testing

Use StreamData for:
- Similarity calculation properties (symmetry, triangle inequality)
- Weight calculation bounds (0.0-1.0)
- Ranking stability
- Collection merging commutativity

### Performance Testing

**Benchmarks:**
- Aggregation time vs. number of reflections
- Similarity calculation performance
- Clustering algorithm scalability
- Memory usage with large datasets

**Targets:**
- Aggregate 100 reflections: <1 second
- Similarity calculation: <1ms per pair
- Memory usage: <100MB for 1000 suggestions

---

## Success Criteria

### Subtask 1.3.4.1: Feedback Collector

- [ ] Collects suggestions from multiple reflections
- [ ] Tracks provenance (source IDs, contexts)
- [ ] Counts suggestion frequencies
- [ ] Integrates edit plan impact data
- [ ] Supports collection merging
- [ ] Tests achieve >95% coverage
- [ ] Documentation complete

### Subtask 1.3.4.2: Pattern Detector

- [ ] Detects recurring failure patterns
- [ ] Identifies suggestion patterns and themes
- [ ] Calculates pattern frequencies
- [ ] Performs statistical significance testing
- [ ] Categorizes patterns accurately
- [ ] Tests achieve >95% coverage
- [ ] Statistical methodology documented

### Subtask 1.3.4.3: Deduplicator

- [ ] Calculates semantic similarity accurately
- [ ] Implements hierarchical deduplication
- [ ] Creates suggestion clusters
- [ ] Generates representative suggestions
- [ ] Configurable similarity thresholds
- [ ] Handles 100+ suggestions efficiently
- [ ] Tests achieve >95% coverage
- [ ] Similarity algorithm documented

### Subtask 1.3.4.4: Weighted Aggregator

- [ ] Calculates confidence weights correctly
- [ ] Computes composite scores
- [ ] Ranks suggestions by priority
- [ ] Filters by confidence threshold
- [ ] Classifies recommendation strength
- [ ] Configurable weight distribution
- [ ] Tests achieve >95% coverage
- [ ] Weighting methodology documented

### Overall Success

- [ ] All subtasks completed
- [ ] End-to-end aggregation pipeline functional
- [ ] Integrates with Tasks 1.3.2 (Reflector) and 1.3.3 (SuggestionGenerator)
- [ ] Output format compatible with Task 1.4 (Mutation Operators)
- [ ] Performance targets met (<1s for 100 reflections)
- [ ] Comprehensive test suite (>95% coverage)
- [ ] All tests passing
- [ ] Complete documentation
- [ ] Usage examples provided
- [ ] Integration guide written

---

## Integration Considerations

### Input Integration (Tasks 1.3.2 & 1.3.3)

**From Reflector (Task 1.3.2):**
```elixir
ParsedReflection.t() provides:
- suggestions: [Suggestion.t()]
- confidence: :high | :medium | :low
- root_causes: [String.t()]
- analysis: String.t()
```

**From SuggestionGenerator (Task 1.3.3):**
```elixir
EditPlan.t() provides:
- edits: [PromptEdit.t()] (ranked by impact)
- high_impact_edits: integer()
- validated: boolean()
```

**Integration Points:**
1. Extract suggestions from ParsedReflection
2. Link suggestions to corresponding edits in EditPlan
3. Aggregate impact scores from edits
4. Preserve all confidence and metadata

### Output Integration (Task 1.4 - Mutation Operators)

**FeedbackAggregator Output:**
```elixir
AggregatedFeedback.t() provides:
- patterns: [FailurePattern.t()]
- suggestions: [WeightedSuggestion.t()]  # Ranked by confidence
- high_confidence: [WeightedSuggestion.t()]
- statistical_significance: [p-values]
```

**Mutation Operator Needs:**
1. **Targeted Mutations**: Use high_confidence suggestions first
2. **Pattern-Based Mutations**: Address recurring failure patterns
3. **Prioritization**: Focus on high composite score suggestions
4. **Diversity**: Balance addressing common patterns vs. unique issues

**Example Workflow:**
```elixir
# Generate population
population = GEPA.Optimizer.evaluate_population(prompts, tasks)

# Collect feedback
reflections = Reflector.reflect_on_failures(population.failures)
edit_plans = SuggestionGenerator.generate_edit_plans(reflections)

# Aggregate feedback
{:ok, aggregated} = FeedbackAggregator.aggregate_feedback(
  reflections: reflections,
  edit_plans: edit_plans
)

# Mutation operators use aggregated feedback
{:ok, mutations} = MutationOperator.mutate_prompts(
  population.prompts,
  guidance: aggregated
)
```

### Data Flow Diagram

```
┌─────────────────────┐
│ Multiple Evaluation │
│    Trajectories     │
└──────────┬──────────┘
           │
           ↓
┌─────────────────────┐
│ Task 1.3.2:         │
│ Reflector           │
│                     │
│ Generates:          │
│ ParsedReflection[]  │
└──────────┬──────────┘
           │
           ↓
┌─────────────────────┐
│ Task 1.3.3:         │
│ SuggestionGenerator │
│                     │
│ Generates:          │
│ EditPlan[]          │
└──────────┬──────────┘
           │
           ↓
┌─────────────────────────────────┐
│ Task 1.3.4: FeedbackAggregator  │
│                                 │
│ 1.3.4.1: Collector              │
│    ↓                            │
│ 1.3.4.2: PatternDetector        │
│    ↓                            │
│ 1.3.4.3: Deduplicator           │
│    ↓                            │
│ 1.3.4.4: WeightedAggregator     │
│                                 │
│ Output: AggregatedFeedback      │
└─────────────┬───────────────────┘
              │
              ↓
┌─────────────────────┐
│ Task 1.4:           │
│ Mutation Operators  │
│                     │
│ Uses:               │
│ AggregatedFeedback  │
└─────────────────────┘
```

### Compatibility Requirements

1. **TypedStruct Consistency**: Use TypedStruct for all data structures
2. **Error Handling**: Return `{:ok, result}` | `{:error, reason}` tuples
3. **Logging**: Use Logger for debugging and instrumentation
4. **Configuration**: Support keyword options for flexibility
5. **Documentation**: Maintain documentation style consistent with existing modules

---

## Risk Mitigation

### Risk 1: Semantic Similarity Complexity

**Risk:** Accurate semantic similarity is challenging without embeddings.

**Mitigation:**
- Start with text-based similarity (Levenshtein, Jaccard)
- Use multiple signals (category, target section, rationale)
- Make similarity threshold configurable
- Document limitations clearly
- Plan for embedding-based similarity in future enhancement

### Risk 2: Statistical Significance with Small Samples

**Risk:** Limited evaluations may not provide statistical power.

**Mitigation:**
- Document minimum evaluation requirements
- Use appropriate statistical tests (binomial test)
- Provide confidence intervals with significance
- Default to pattern detection when sample too small
- Warn users about low-confidence patterns

### Risk 3: Performance with Large Datasets

**Risk:** O(n²) similarity calculations may be slow for many suggestions.

**Mitigation:**
- Implement efficient clustering algorithms
- Use early stopping for obviously dissimilar pairs
- Consider sampling for very large datasets (>1000 suggestions)
- Add performance benchmarks to tests
- Profile and optimize hot paths

### Risk 4: Integration Complexity

**Risk:** Coordinating multiple modules and data structures.

**Mitigation:**
- Clear interface contracts between modules
- Comprehensive integration tests
- Document data flow explicitly
- Use consistent error handling patterns
- Add instrumentation for debugging

### Risk 5: Over-Deduplication

**Risk:** Merging truly different suggestions incorrectly.

**Mitigation:**
- Conservative similarity thresholds (default 0.7)
- Manual review of clusters in testing
- Preserve cluster membership data
- Allow configuration of aggressiveness
- Provide deduplication statistics in output

### Risk 6: Weight Tuning Challenges

**Risk:** Composite score weights may need adjustment.

**Mitigation:**
- Use research-informed defaults
- Make all weights configurable
- Add weight sensitivity analysis to tests
- Document weight tuning methodology
- Plan for adaptive weighting in future

---

## Future Enhancements

**Phase 3 Potential Improvements:**

1. **Embedding-Based Similarity**
   - Use sentence embeddings for semantic similarity
   - Integrate with existing embedding system (Task 1.3.3)
   - Improve deduplication accuracy

2. **Adaptive Weighting**
   - Learn optimal weights from optimization outcomes
   - Adjust weights based on mutation success rates
   - Meta-learning across optimization runs

3. **Multi-Objective Aggregation**
   - Aggregate differently for different objectives
   - Balance trade-offs in Pareto optimization
   - Objective-specific pattern detection

4. **Temporal Patterns**
   - Track patterns across generations
   - Detect emerging vs. persistent patterns
   - Time-weighted aggregation

5. **Active Learning**
   - Identify ambiguous cases needing clarification
   - Request targeted multi-turn reflection
   - Reduce aggregation uncertainty

---

## Timeline Estimate

- **Phase 1 (Collector)**: 3-4 hours
  - Data structures: 1 hour
  - Collection logic: 1 hour
  - Edit plan integration: 0.5 hours
  - Collection merging: 0.5 hours
  - Testing: 1 hour

- **Phase 2 (Pattern Detector)**: 4-5 hours
  - Data structures: 1 hour
  - Failure pattern detection: 1.5 hours
  - Suggestion pattern detection: 1 hour
  - Statistical testing: 1 hour
  - Testing: 1.5 hours

- **Phase 3 (Deduplicator)**: 4-5 hours
  - Similarity calculation: 2 hours
  - Clustering implementation: 1.5 hours
  - Representative creation: 0.5 hours
  - Testing: 1.5 hours

- **Phase 4 (Weighted Aggregator)**: 3-4 hours
  - Weighting logic: 1.5 hours
  - Ranking and filtering: 1 hour
  - Testing: 1.5 hours

- **Phase 5 (Integration)**: 3-4 hours
  - Main orchestrator: 1.5 hours
  - Output structure: 1 hour
  - Integration testing: 1.5 hours

- **Phase 6 (Testing & Docs)**: 3-4 hours
  - Additional tests: 1.5 hours
  - Documentation: 1.5-2 hours
  - Integration guide: 0.5-1 hour

**Total: 20-26 hours**

---

## Conclusion

Task 1.3.4 implements the critical feedback aggregation system that enables GEPA to:

1. **Extract Robust Patterns**: Distinguish signal from noise across multiple evaluations
2. **Remove Redundancy**: Deduplicate semantically similar suggestions
3. **Prioritize Intelligently**: Weight suggestions by confidence, frequency, and impact
4. **Enable Sample Efficiency**: Extract maximum insight from limited evaluations

The implementation provides:
- **Modular Architecture**: Four specialized components (Collector, PatternDetector, Deduplicator, WeightedAggregator)
- **Statistical Rigor**: Significance testing and confidence weighting
- **Flexible Configuration**: Tunable thresholds and weights
- **Strong Integration**: Clean interfaces with Tasks 1.3.2, 1.3.3, and 1.4
- **Comprehensive Testing**: >95% coverage with performance benchmarks

This completes Section 1.3 (Reflection & Feedback Generation) and provides the foundation for effective mutation operators in Task 1.4, ultimately enabling GEPA's 35x sample efficiency advantage over traditional reinforcement learning approaches.
