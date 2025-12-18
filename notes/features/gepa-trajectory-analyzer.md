# Feature Planning Document: GEPA Trajectory Analysis (Section 1.3.1)

**Feature ID**: GEPA-1.3.1
**Created**: 2025-10-22
**Status**: Planning Phase
**Implementation Phase**: Phase 5 - GEPA Prompt Optimization
**Related Documents**: notes/planning/phase-05.md (lines 148-156)

---

## 1. Problem Statement

### Overview
The GEPA (Genetic-Pareto) Prompt Optimization system needs to analyze execution trajectories to extract insights that guide LLM-guided reflection. Currently, we have a comprehensive Trajectory collection system (Section 1.2.2) that captures execution paths, but we lack the analysis layer that identifies failure patterns, logical inconsistencies, and success patterns.

### Why This Matters
This is a critical component of GEPA's key innovation: using LLM language understanding to interpret failures and propose specific prompt modifications rather than relying on opaque gradient signals. Without trajectory analysis:

1. **No Failure Insights**: Cannot identify what went wrong or where in the execution path
2. **No Pattern Recognition**: Cannot detect recurring error patterns across evaluations
3. **No Success Learning**: Cannot extract what made high-performing executions succeed
4. **No Comparative Analysis**: Cannot understand differences between successful and failed attempts

### Impact
- **Blocks Section 1.3.2**: LLM-Guided Reflection depends on structured analysis output
- **Blocks Section 1.3.3**: Improvement suggestions need failure/success patterns
- **Affects Optimization Quality**: Poor analysis leads to poor prompt improvements

---

## 2. Solution Overview

### High-Level Approach

Create a `Jido.Runner.GEPA.TrajectoryAnalyzer` module that processes trajectory data and produces structured analysis for LLM reflection. The analyzer will:

1. **Parse Trajectories**: Extract relevant information from Trajectory structs
2. **Identify Failures**: Pinpoint where and why executions failed
3. **Detect Inconsistencies**: Find logical gaps in reasoning chains
4. **Extract Patterns**: Identify success patterns from high-performing trajectories
5. **Compare Trajectories**: Analyze differences between successful and failed attempts

### Design Decisions

**Pure Functional Design**
- All analysis functions are pure, accepting trajectory data and returning analysis results
- No state management required - analysis is stateless
- Enables easy testing and composition

**Structured Output for LLM Consumption**
- Analysis results are maps with standardized keys
- Natural language descriptions alongside structured data
- Designed to be serializable for LLM prompts

**Multi-Level Analysis**
- Individual trajectory analysis (single execution path)
- Batch analysis (multiple trajectories from same prompt)
- Comparative analysis (successful vs failed trajectories)

**Pattern Detection Approach**
- Step-level analysis: Examine individual reasoning/action steps
- Sequence-level analysis: Look at step transitions and flow
- Outcome-level analysis: Correlate patterns with success/failure
- Statistical analysis: Use Metrics module for quantitative patterns

---

## 3. Agent Consultations Performed

### Elixir/OTP Expert Consultation

**Topic**: Elixir patterns for trajectory analysis and pattern detection

**Key Recommendations**:
1. Use pattern matching on step types for analysis dispatch
2. Leverage `Enum.reduce` for accumulating patterns across steps
3. Use `Enum.group_by` for categorizing failures by type
4. Consider `Stream` for large trajectory collections
5. Use TypedStruct for analysis result structures
6. Implement protocol for extensible analysis types if needed

**Code Patterns**:
```elixir
# Pattern match on step types
def analyze_step(%Step{type: :reasoning} = step), do: analyze_reasoning(step)
def analyze_step(%Step{type: :action} = step), do: analyze_action(step)

# Accumulate patterns with reduce
def find_patterns(steps) do
  Enum.reduce(steps, %{patterns: [], context: %{}}, fn step, acc ->
    # Accumulate pattern detection
  end)
end

# Group failures by category
def categorize_failures(trajectories) do
  trajectories
  |> Enum.filter(&(&1.outcome == :failure))
  |> Enum.group_by(&classify_failure/1)
end
```

### Architecture Consultation

**Topic**: Integration with existing GEPA components

**Key Decisions**:
1. **Position in Flow**: Analyzer sits between Evaluator (1.2.1) and Reflection (1.3.2)
2. **Data Dependencies**: Consumes Trajectory structs, produces Analysis structs
3. **Integration Points**:
   - Input: Trajectory from Evaluator.evaluate_prompt/2
   - Output: Analysis map for LLM Reflection prompts
   - Side channel: Metrics for statistical pattern detection

4. **Extensibility**: Design for future analysis types (not just failure/success)

---

## 4. Technical Details

### Module Location
- **Primary Module**: `lib/jido/runner/gepa/trajectory_analyzer.ex`
- **Test File**: `test/jido/runner/gepa/trajectory_analyzer_test.exs`

### Dependencies

**Existing Modules**:
- `Jido.Runner.GEPA.Trajectory` - Source of trajectory data structures
- `Jido.Runner.GEPA.Trajectory.Step` - Individual step analysis
- `Jido.Runner.GEPA.Trajectory.StateSnapshot` - State analysis
- `Jido.Runner.GEPA.Metrics` - Statistical aggregation support

**Standard Library**:
- `Enum` - Collection processing
- `Map` - Result structure building
- `DateTime` - Timing analysis
- `Logger` - Debug logging

### Key Data Structures

```elixir
# Analysis Result for a Single Trajectory
typedstruct module: TrajectoryAnalysis do
  field(:trajectory_id, String.t(), enforce: true)
  field(:outcome, Trajectory.outcome(), enforce: true)
  field(:failure_points, list(FailurePoint.t()), default: [])
  field(:reasoning_issues, list(ReasoningIssue.t()), default: [])
  field(:success_indicators, list(SuccessIndicator.t()), default: [])
  field(:step_summary, map(), default: %{})
  field(:metadata, map(), default: %{})
end

# Failure Point Identification
typedstruct module: FailurePoint do
  field(:step_id, String.t(), enforce: true)
  field(:step_index, non_neg_integer(), enforce: true)
  field(:failure_type, atom(), enforce: true) # :error, :timeout, :invalid_action, :logical_error
  field(:description, String.t(), enforce: true)
  field(:context, map(), default: %{})
  field(:state_at_failure, map() | nil)
end

# Reasoning Step Issues
typedstruct module: ReasoningIssue do
  field(:step_id, String.t(), enforce: true)
  field(:issue_type, atom(), enforce: true) # :inconsistency, :leap, :circular, :incomplete
  field(:description, String.t(), enforce: true)
  field(:severity, atom(), default: :medium) # :low, :medium, :high
end

# Success Pattern Indicators
typedstruct module: SuccessIndicator do
  field(:pattern_type, atom(), enforce: true) # :reasoning_depth, :tool_usage, :validation, :structure
  field(:description, String.t(), enforce: true)
  field(:frequency, non_neg_integer(), default: 1)
  field(:correlation_score, float() | nil)
end

# Comparative Analysis Result
typedstruct module: ComparativeAnalysis do
  field(:successful_trajectories, list(String.t()), default: [])
  field(:failed_trajectories, list(String.t()), default: [])
  field(:key_differences, list(Difference.t()), default: [])
  field(:common_success_patterns, list(SuccessIndicator.t()), default: [])
  field(:common_failure_patterns, list(FailurePoint.t()), default: [])
  field(:recommendations, list(String.t()), default: [])
end

typedstruct module: Difference do
  field(:category, atom(), enforce: true) # :step_count, :reasoning_depth, :tool_usage, etc.
  field(:description, String.t(), enforce: true)
  field(:successful_value, term())
  field(:failed_value, term())
  field(:significance, float() | nil)
end
```

### Public API

```elixir
@doc """
Analyzes a single trajectory to identify failure points and patterns.

## Parameters
- `trajectory` - Trajectory struct to analyze
- `opts` - Options:
  - `:detailed` - Include detailed step-by-step analysis (default: true)
  - `:include_state` - Include state snapshots in analysis (default: true)

## Returns
- `{:ok, TrajectoryAnalysis.t()}` - Successful analysis
- `{:error, reason}` - Analysis failed

## Examples

    {:ok, analysis} = TrajectoryAnalyzer.analyze(trajectory)
    analysis.failure_points
    # => [%FailurePoint{step_id: "step_123", failure_type: :timeout, ...}]
"""
@spec analyze(Trajectory.t(), keyword()) ::
  {:ok, TrajectoryAnalysis.t()} | {:error, term()}

@doc """
Analyzes multiple trajectories to identify error patterns and trends.

Useful for detecting recurring failure modes across multiple evaluations
of the same prompt or similar prompts.

## Parameters
- `trajectories` - List of Trajectory structs
- `opts` - Options:
  - `:min_frequency` - Minimum pattern occurrence (default: 2)
  - `:failure_only` - Only analyze failed trajectories (default: false)

## Returns
- `{:ok, list(pattern)}` - List of detected patterns
- `{:error, reason}` - Analysis failed

## Examples

    {:ok, patterns} = TrajectoryAnalyzer.find_error_patterns(trajectories)
    # => [
    #   %{type: :timeout, frequency: 5, description: "Tool calls timing out"},
    #   %{type: :logical_error, frequency: 3, description: "Missing validation step"}
    # ]
"""
@spec find_error_patterns(list(Trajectory.t()), keyword()) ::
  {:ok, list(map())} | {:error, term()}

@doc """
Analyzes reasoning steps to detect logical inconsistencies.

Examines chains of reasoning steps for:
- Logical leaps without justification
- Contradictory statements
- Circular reasoning
- Incomplete reasoning chains

## Parameters
- `trajectory` - Trajectory to analyze
- `opts` - Options:
  - `:reasoning_only` - Only analyze reasoning-type steps (default: true)
  - `:min_severity` - Minimum issue severity to report (default: :medium)

## Returns
- `{:ok, list(ReasoningIssue.t())}` - List of detected issues
- `{:error, reason}` - Analysis failed

## Examples

    {:ok, issues} = TrajectoryAnalyzer.analyze_reasoning_steps(trajectory)
    # => [
    #   %ReasoningIssue{
    #     issue_type: :inconsistency,
    #     description: "Step 3 contradicts conclusion from step 1"
    #   }
    # ]
"""
@spec analyze_reasoning_steps(Trajectory.t(), keyword()) ::
  {:ok, list(ReasoningIssue.t())} | {:error, term()}

@doc """
Extracts success patterns from high-performing trajectories.

Identifies what made successful executions work:
- Reasoning depth and structure
- Effective tool usage patterns
- Validation and checking behaviors
- Step sequencing

## Parameters
- `trajectories` - List of successful Trajectory structs
- `opts` - Options:
  - `:min_quality_threshold` - Minimum quality score (default: 0.8)
  - `:include_correlations` - Calculate pattern correlations (default: true)

## Returns
- `{:ok, list(SuccessIndicator.t())}` - List of success patterns
- `{:error, reason}` - Analysis failed

## Examples

    successful_trajectories = Enum.filter(trajectories, &(&1.outcome == :success))
    {:ok, patterns} = TrajectoryAnalyzer.extract_success_patterns(successful_trajectories)
    # => [
    #   %SuccessIndicator{
    #     pattern_type: :reasoning_depth,
    #     description: "Average 5 reasoning steps before action",
    #     frequency: 8
    #   }
    # ]
"""
@spec extract_success_patterns(list(Trajectory.t()), keyword()) ::
  {:ok, list(SuccessIndicator.t())} | {:error, term()}

@doc """
Compares successful and failed trajectories to identify key differences.

Performs comparative analysis to understand what distinguishes
successful executions from failures. This is crucial for LLM
reflection to propose targeted improvements.

## Parameters
- `successful_trajectories` - List of successful Trajectory structs
- `failed_trajectories` - List of failed Trajectory structs
- `opts` - Options:
  - `:statistical_threshold` - Min significance for differences (default: 0.05)
  - `:include_recommendations` - Generate recommendations (default: true)

## Returns
- `{:ok, ComparativeAnalysis.t()}` - Comparative analysis result
- `{:error, reason}` - Analysis failed

## Examples

    {:ok, comparison} = TrajectoryAnalyzer.compare_trajectories(
      successful_trajectories,
      failed_trajectories
    )

    comparison.key_differences
    # => [
    #   %Difference{
    #     category: :reasoning_depth,
    #     description: "Successful trajectories have more reasoning steps",
    #     successful_value: 6.2,
    #     failed_value: 2.8
    #   }
    # ]
"""
@spec compare_trajectories(
  list(Trajectory.t()),
  list(Trajectory.t()),
  keyword()
) :: {:ok, ComparativeAnalysis.t()} | {:error, term()}

@doc """
Generates a natural language summary of trajectory analysis.

Produces human-readable (and LLM-consumable) description of
what happened during trajectory execution and what issues
were identified. Used as input to LLM reflection.

## Parameters
- `analysis` - TrajectoryAnalysis struct
- `opts` - Options:
  - `:format` - Output format: :text or :structured (default: :text)
  - `:verbosity` - Detail level: :brief, :normal, :detailed (default: :normal)

## Returns
- `{:ok, String.t()}` - Natural language summary
- `{:error, reason}` - Generation failed

## Examples

    {:ok, analysis} = TrajectoryAnalyzer.analyze(trajectory)
    {:ok, summary} = TrajectoryAnalyzer.summarize(analysis)
    # => "Execution failed at step 5 (tool_call) due to timeout.
    #     The reasoning chain showed 3 logical steps before failure.
    #     No state snapshots captured at failure point.
    #     Common pattern: insufficient validation before tool call."
"""
@spec summarize(TrajectoryAnalysis.t(), keyword()) ::
  {:ok, String.t()} | {:error, term()}
```

---

## 5. Success Criteria

### Functional Requirements

**Must Have**:
- [ ] Correctly identify failure points in trajectories with error outcomes
- [ ] Detect at least 4 types of reasoning inconsistencies
- [ ] Extract success patterns from high-performing trajectories
- [ ] Compare successful vs failed trajectories and identify key differences
- [ ] Generate natural language summaries suitable for LLM consumption
- [ ] Handle edge cases: empty trajectories, partial trajectories, timeout cases

**Should Have**:
- [ ] Statistical significance testing for pattern detection
- [ ] Configurable analysis depth and verbosity
- [ ] Support for batch processing multiple trajectories efficiently
- [ ] Correlation analysis between patterns and outcomes

**Nice to Have**:
- [ ] Visual trajectory comparison (text-based)
- [ ] Pattern caching for repeated analysis
- [ ] Export analysis to structured formats (JSON, etc.)

### Non-Functional Requirements

**Performance**:
- Single trajectory analysis: < 100ms for typical trajectory (10-50 steps)
- Batch analysis: < 1s for 10 trajectories
- Comparative analysis: < 2s for 20 trajectories (10 successful, 10 failed)

**Quality**:
- 100% test coverage for core analysis functions
- All edge cases handled with clear error messages
- Comprehensive documentation with examples

**Integration**:
- Clean integration with Trajectory module
- Natural output format for LLM Reflection (1.3.2)
- Support for Metrics aggregation patterns

---

## 6. Implementation Plan

### Step 1: Setup Module Structure and Basic Analysis (1.3.1.1)

**Status**: ⏳ Not Started

**Goal**: Create the TrajectoryAnalyzer module skeleton and implement basic failure point identification.

**Tasks**:
1. Create module file with TypedStruct definitions
   - TrajectoryAnalysis
   - FailurePoint
   - Basic module structure with @moduledoc

2. Implement `analyze/2` function
   - Accept Trajectory struct
   - Extract basic information (outcome, duration, step count)
   - Identify failure points for error/timeout outcomes
   - Return TrajectoryAnalysis struct

3. Implement failure point detection
   - Scan steps for error indicators
   - Check state snapshots for failure context
   - Extract error information from trajectory.error
   - Classify failure types (:error, :timeout, :invalid_action)

4. Write initial tests
   - Test successful trajectory analysis (no failure points)
   - Test failed trajectory with timeout
   - Test failed trajectory with error at specific step
   - Test edge cases (empty steps, missing data)

**Files to Create/Modify**:
- `lib/jido/runner/gepa/trajectory_analyzer.ex` (create)
- `test/jido/runner/gepa/trajectory_analyzer_test.exs` (create)

**Success Criteria**:
- Module compiles without warnings
- Basic analysis returns TrajectoryAnalysis struct
- Failure points correctly identified in test cases
- All tests pass

**Dependencies**: None (uses existing Trajectory module)

---

### Step 2: Reasoning Step Analysis (1.3.1.2)

**Status**: ⏳ Not Started

**Goal**: Implement detection of logical inconsistencies in reasoning chains.

**Tasks**:
1. Add ReasoningIssue TypedStruct
   - Define issue types and severity levels
   - Add to module type definitions

2. Implement `analyze_reasoning_steps/2`
   - Filter for reasoning-type steps
   - Check for logical leaps (missing intermediate steps)
   - Detect contradictory statements
   - Identify circular reasoning patterns
   - Detect incomplete chains

3. Add step sequence analysis
   - Analyze step-to-step transitions
   - Check for reasoning continuity
   - Identify gaps in logic flow

4. Write reasoning analysis tests
   - Test detection of logical leaps
   - Test contradiction detection
   - Test circular reasoning detection
   - Test complete vs incomplete chains
   - Test severity classification

**Files to Modify**:
- `lib/jido/runner/gepa/trajectory_analyzer.ex`
- `test/jido/runner/gepa/trajectory_analyzer_test.exs`

**Success Criteria**:
- Detects at least 4 types of reasoning issues
- Correctly classifies issue severity
- Returns empty list for valid reasoning chains
- All tests pass

**Dependencies**: Step 1 complete

---

### Step 3: Success Pattern Extraction (1.3.1.3)

**Status**: ⏳ Not Started

**Goal**: Extract and identify patterns from high-performing trajectory executions.

**Tasks**:
1. Add SuccessIndicator TypedStruct
   - Define pattern types
   - Add correlation scoring

2. Implement `extract_success_patterns/2`
   - Filter successful trajectories
   - Analyze reasoning depth patterns
   - Identify effective tool usage
   - Detect validation behaviors
   - Extract step sequencing patterns

3. Add pattern frequency analysis
   - Count pattern occurrences
   - Calculate pattern prevalence
   - Filter by minimum frequency

4. Add correlation analysis
   - Correlate patterns with quality metrics
   - Score pattern significance

5. Write pattern extraction tests
   - Test pattern detection in successful trajectories
   - Test frequency counting
   - Test correlation scoring
   - Test filtering by quality threshold
   - Test edge cases (single trajectory, no patterns)

**Files to Modify**:
- `lib/jido/runner/gepa/trajectory_analyzer.ex`
- `test/jido/runner/gepa/trajectory_analyzer_test.exs`

**Success Criteria**:
- Identifies multiple pattern types
- Correctly counts pattern frequency
- Calculates meaningful correlations
- All tests pass

**Dependencies**: Step 1 complete

---

### Step 4: Comparative Analysis (1.3.1.4)

**Status**: ⏳ Not Started

**Goal**: Implement comparison between successful and failed trajectories to identify key differences.

**Tasks**:
1. Add ComparativeAnalysis and Difference TypedStructs
   - Define difference categories
   - Add significance scoring

2. Implement `compare_trajectories/3`
   - Accept lists of successful and failed trajectories
   - Calculate aggregate statistics for each group
   - Identify statistically significant differences
   - Generate key difference descriptions

3. Add pattern comparison
   - Compare success patterns between groups
   - Identify patterns unique to successful trajectories
   - Identify common failure patterns

4. Add recommendation generation
   - Based on key differences, suggest improvements
   - Prioritize recommendations by significance

5. Write comparative analysis tests
   - Test comparison with clear differences
   - Test comparison with similar trajectories
   - Test statistical significance calculation
   - Test recommendation generation
   - Test edge cases (unequal groups, small samples)

**Files to Modify**:
- `lib/jido/runner/gepa/trajectory_analyzer.ex`
- `test/jido/runner/gepa/trajectory_analyzer_test.exs`

**Success Criteria**:
- Identifies statistically significant differences
- Generates actionable recommendations
- Handles edge cases gracefully
- All tests pass

**Dependencies**: Steps 1-3 complete

---

### Step 5: Pattern Detection and Aggregation (1.3.1.1 - Error Patterns)

**Status**: ⏳ Not Started

**Goal**: Implement batch analysis to detect recurring error patterns across multiple trajectories.

**Tasks**:
1. Implement `find_error_patterns/2`
   - Accept list of trajectories
   - Group failures by type
   - Calculate pattern frequency
   - Generate pattern descriptions

2. Add pattern clustering
   - Group similar failure points
   - Identify recurring sequences
   - Calculate pattern significance

3. Add temporal pattern analysis
   - Detect time-based patterns (early vs late failures)
   - Analyze failure progression

4. Write pattern detection tests
   - Test single pattern detection
   - Test multiple recurring patterns
   - Test frequency thresholds
   - Test pattern clustering
   - Test with mixed successful/failed trajectories

**Files to Modify**:
- `lib/jido/runner/gepa/trajectory_analyzer.ex`
- `test/jido/runner/gepa/trajectory_analyzer_test.exs`

**Success Criteria**:
- Detects recurring patterns across trajectories
- Correctly calculates frequencies
- Filters by minimum occurrence threshold
- All tests pass

**Dependencies**: Steps 1-2 complete

---

### Step 6: Natural Language Summary Generation

**Status**: ⏳ Not Started

**Goal**: Generate human/LLM-readable summaries of trajectory analysis.

**Tasks**:
1. Implement `summarize/2`
   - Accept TrajectoryAnalysis struct
   - Generate natural language descriptions
   - Support multiple verbosity levels
   - Format for LLM consumption

2. Add summary templates
   - Create templates for different analysis types
   - Include failure point descriptions
   - Include reasoning issue summaries
   - Include success pattern highlights

3. Add structured output option
   - Support both text and structured formats
   - Enable JSON serialization

4. Write summary generation tests
   - Test all verbosity levels
   - Test different trajectory outcomes
   - Test with various analysis results
   - Test structured vs text output

**Files to Modify**:
- `lib/jido/runner/gepa/trajectory_analyzer.ex`
- `test/jido/runner/gepa/trajectory_analyzer_test.exs`

**Success Criteria**:
- Generates clear, actionable summaries
- Supports multiple output formats
- Summaries suitable for LLM reflection
- All tests pass

**Dependencies**: Steps 1-5 complete

---

### Step 7: Integration Testing and Documentation

**Status**: ⏳ Not Started

**Goal**: Comprehensive testing with real trajectory data and complete documentation.

**Tasks**:
1. Create integration test suite
   - Use real Trajectory fixtures from evaluator
   - Test full analysis pipeline
   - Test with diverse trajectory types
   - Test performance with batch processing

2. Add property-based tests (if appropriate)
   - Test invariants across random inputs
   - Test pattern detection robustness

3. Complete module documentation
   - Add comprehensive @moduledoc
   - Add examples for all public functions
   - Document all TypedStruct fields
   - Add usage examples

4. Performance testing and optimization
   - Profile analysis functions
   - Optimize hot paths if needed
   - Ensure performance criteria met

5. Create usage guide
   - Document integration with Evaluator
   - Show example workflows
   - Document output formats for LLM Reflection

**Files to Modify**:
- `lib/jido/runner/gepa/trajectory_analyzer.ex`
- `test/jido/runner/gepa/trajectory_analyzer_test.exs`
- `test/jido/runner/gepa/trajectory_analyzer_integration_test.exs` (create)

**Success Criteria**:
- All integration tests pass
- Performance requirements met
- 100% documentation coverage
- Clear usage examples provided

**Dependencies**: Steps 1-6 complete

---

## 7. Testing Strategy

### Unit Tests

**Coverage Requirements**: 100% for core analysis functions

**Test Categories**:

1. **Analysis Function Tests**
   - Valid inputs produce expected outputs
   - Edge cases handled correctly
   - Error cases return appropriate errors

2. **Pattern Detection Tests**
   - Patterns correctly identified
   - Frequency counting accurate
   - Filtering works as expected

3. **Reasoning Analysis Tests**
   - Inconsistency detection accurate
   - Severity classification correct
   - Edge cases handled

4. **Comparative Analysis Tests**
   - Differences correctly identified
   - Statistical significance calculated
   - Recommendations generated

5. **Summary Generation Tests**
   - Summaries are coherent
   - All verbosity levels work
   - Output formats correct

### Integration Tests

**Test Scenarios**:

1. **End-to-End Pipeline**
   - Trajectory → Analysis → Summary → LLM Reflection
   - Multiple trajectories → Pattern Detection
   - Batch processing performance

2. **Real Data Tests**
   - Use actual trajectories from evaluator tests
   - Test with diverse trajectory types
   - Test with edge cases from real usage

3. **Performance Tests**
   - Measure analysis time for various inputs
   - Test batch processing efficiency
   - Ensure performance criteria met

### Test Data Strategy

**Fixtures**:
- Create comprehensive trajectory fixtures covering:
  - Successful trajectories (high quality)
  - Failed trajectories (various failure types)
  - Partial trajectories (timeout, incomplete)
  - Edge cases (empty, single step, very long)

**Test Helpers**:
- Builder functions for creating test trajectories
- Factory functions for common patterns
- Assertion helpers for analysis validation

---

## 8. Notes and Considerations

### Implementation Notes

1. **Pattern Detection Approach**
   - Start with simple rule-based detection
   - Consider ML-based pattern detection in future (if needed)
   - Keep detection logic extensible

2. **Performance Considerations**
   - Use `Stream` for large trajectory batches
   - Consider caching for repeated analysis
   - Profile before optimizing

3. **Extensibility**
   - Design for new analysis types
   - Consider protocol-based approach for custom analyzers
   - Keep analysis functions composable

### Integration Considerations

1. **With Evaluator (1.2.1)**
   - Evaluator provides trajectories
   - Consider adding analysis call to evaluator pipeline
   - May need to batch analyze for efficiency

2. **With Reflection (1.3.2)**
   - Analysis output becomes reflection input
   - Summary format must be LLM-friendly
   - Consider structured vs natural language trade-offs

3. **With Metrics (1.2.3)**
   - Use Metrics for statistical analysis
   - Correlate patterns with metrics
   - Share statistical functions where possible

### Edge Cases and Risks

**Edge Cases**:
- Empty trajectories (no steps)
- Partial trajectories (incomplete execution)
- Very long trajectories (performance concern)
- Trajectories with missing data (incomplete snapshots)
- Single trajectory analysis (no patterns possible)

**Risks**:
- Pattern detection false positives (over-sensitive)
- Pattern detection false negatives (under-sensitive)
- Performance issues with large batches
- Summary generation too verbose or too brief
- Reasoning inconsistency detection too simplistic

**Mitigations**:
- Comprehensive testing with edge cases
- Configurable thresholds and sensitivity
- Performance testing and optimization
- Iterative refinement based on real usage
- Consult with LLM Reflection implementation for summary format

### Future Enhancements

1. **Advanced Pattern Detection**
   - Machine learning-based pattern recognition
   - Cross-trajectory pattern correlation
   - Temporal pattern analysis

2. **Visualization**
   - Trajectory visualization for debugging
   - Pattern heatmaps
   - Comparative visualizations

3. **Caching and Optimization**
   - Cache analysis results
   - Incremental analysis for updated trajectories
   - Parallel batch processing

4. **Custom Analyzers**
   - Plugin system for domain-specific analysis
   - Protocol-based extensibility
   - Community-contributed analyzers

---

## 9. Dependencies and Blockers

### Dependencies

**Internal**:
- ✅ Jido.Runner.GEPA.Trajectory (Section 1.2.2) - Complete
- ✅ Jido.Runner.GEPA.Metrics (Section 1.2.3) - Complete
- ✅ Jido.Runner.GEPA.Evaluator (Section 1.2.1) - Complete

**External**:
- None (uses only Elixir standard library)

### Blocks

This implementation blocks:
- **Section 1.3.2**: LLM-Guided Reflection (needs analysis output)
- **Section 1.3.3**: Improvement Suggestion Generation (needs patterns)
- **Section 1.3.4**: Feedback Aggregation (needs pattern detection)

### Prerequisites

**Before Starting**:
- ✅ Review existing Trajectory module and tests
- ✅ Review similar analysis patterns in codebase
- ✅ Understand LLM Reflection requirements (review Section 1.3.2 plan)

---

## 10. Implementation Checklist

### Pre-Implementation
- [ ] Review this planning document with Pascal
- [ ] Confirm on correct feature branch (feature/gepa-1.2-unit-tests)
- [ ] Review Section 1.3.2 requirements (LLM Reflection)
- [ ] Study existing trajectory test fixtures

### Implementation Steps
- [ ] Step 1: Setup Module Structure and Basic Analysis (1.3.1.1)
- [ ] Step 2: Reasoning Step Analysis (1.3.1.2)
- [ ] Step 3: Success Pattern Extraction (1.3.1.3)
- [ ] Step 4: Comparative Analysis (1.3.1.4)
- [ ] Step 5: Pattern Detection and Aggregation (1.3.1.1)
- [ ] Step 6: Natural Language Summary Generation
- [ ] Step 7: Integration Testing and Documentation

### Post-Implementation
- [ ] All unit tests pass
- [ ] All integration tests pass
- [ ] Performance criteria met
- [ ] Documentation complete
- [ ] Code review (if needed)
- [ ] Update phase-05.md planning document
- [ ] Ready for Section 1.3.2 implementation

---

## 11. Questions for Pascal

Before starting implementation, please confirm:

1. **Analysis Depth**: Should reasoning inconsistency detection include semantic analysis (requires LLM calls), or is syntactic/structural analysis sufficient for now?

2. **Pattern Detection**: What's the minimum frequency threshold for pattern detection? (Currently planning default of 2)

3. **Performance Priority**: Are the stated performance targets appropriate, or should I optimize for different scenarios?

4. **LLM Reflection Format**: Have you reviewed Section 1.3.2 requirements? What format should the analysis summary use? (Natural language? Structured? Both?)

5. **Test Coverage**: Do you want property-based testing in addition to example-based tests?

6. **Integration Point**: Should trajectory analysis be automatically called by the Evaluator, or should it be a separate step?

---

## 12. Current Status

**Phase**: Planning Complete - Awaiting Confirmation

**Next Action**: Review with Pascal and get answers to questions above

**Ready to Implement**: Once questions answered and plan approved

**Estimated Implementation Time**: 3-4 sessions (assuming ~1 session per major step)

---

*This document follows the feature planning structure recommended in `.claude/commands/feature.md` and incorporates Elixir/OTP best practices for the GEPA Trajectory Analysis implementation.*
