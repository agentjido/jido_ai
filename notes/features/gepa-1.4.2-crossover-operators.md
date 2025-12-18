# GEPA Task 1.4.2: Crossover & Combination Operators - Feature Planning

## Overview

This document provides comprehensive planning for implementing GEPA Task 1.4.2: Crossover & Combination Operators. This task implements genetic crossover operations that combine successful elements from multiple high-performing prompts to create offspring prompts that potentially inherit the best traits from both parents. Unlike mutation operators (Task 1.4.1) which modify individual prompts, crossover operators create entirely new prompts by blending two or more parent prompts.

## Status

- **Phase**: 5 (GEPA Optimization)
- **Stage**: 1 (Foundation)
- **Section**: 1.4 (Mutation & Variation Strategies)
- **Task**: 1.4.2 (Crossover & Combination)
- **Status**: Planning
- **Branch**: TBD (suggest: `feature/gepa-1.4.2-crossover-operators`)

## Prerequisites Completed

### Task 1.3.3: Suggestion Generation ✅
- SuggestionGenerator module converting LLM suggestions to concrete edits
- PromptStructureAnalyzer identifying prompt sections and patterns
- EditPlan data structure with validated, ranked edits
- PromptLocation, PromptEdit, PromptStructure data types

### Task 1.4.1: Targeted Mutation Operators ✅
- Core infrastructure: TextOperations, LocationResolver
- Four mutation operators: EditMutation, AdditionMutation, DeletionMutation, ReplacementMutation
- Integration layer: Orchestrator, Validator, History
- All operators working with PromptStructure for location-aware edits

## Context & Motivation

### The Critical Distinction: Mutation vs. Crossover

**Mutation (Task 1.4.1)** modifies a SINGLE prompt:
- "Add step-by-step instruction" → Modified Prompt A
- "Remove redundant preamble" → Modified Prompt B
- Works with one parent, produces one offspring

**Crossover (Task 1.4.2)** combines MULTIPLE prompts:
- Prompt A (excellent reasoning structure) + Prompt B (clear constraints) → Offspring C (both traits)
- Takes two or more parents, produces one or more offspring
- Inherits complementary strengths from different prompts

### Why Crossover Matters for GEPA

In genetic algorithms, crossover is often MORE IMPORTANT than mutation for several reasons:

1. **Combines Successful Strategies**: High-performing prompts excel in different areas. Crossover lets us combine a prompt with great reasoning steps and another with effective examples.

2. **Accelerates Evolution**: Crossover can make large beneficial changes in one step that would require many mutations to achieve incrementally.

3. **Explores Novel Combinations**: Creates prompt variations that neither parent had, discovering unexpected synergies.

4. **Maintains Population Diversity**: Prevents premature convergence by constantly mixing genetic material.

5. **Leverages Modularity**: Prompts have natural structure (instructions, constraints, examples, formatting). Crossover exploits this modularity.

### Research-Backed Crossover for Prompts

Recent research on prompt optimization with genetic algorithms (GAAPO, EvoPrompt, LMX) shows:

- **GAAPO**: Splits prompts at midpoint, combines first half of one with second half of another
- **EvoPrompt**: Uses roulette wheel selection, combines parent components via LLM
- **LMX (Language Model Crossover)**: Concatenates parents into a prompt, generates offspring via LLM
- **GeneticPromptLab**: Enhances diversity through iterative crossover and mutation

Key insight: Prompt crossover works best when it respects prompt structure and semantics, not just treating prompts as strings.

### GEPA's Evolutionary Pipeline

```
[Population of Prompts]
    ↓
Selection (choose high-performers)
    ↓
Crossover (THIS TASK) ← Combine parents
    ↓
Mutation (Task 1.4.1) ← Refine offspring
    ↓
Evaluation
    ↓
[Next Generation]
```

## Problem Statement

### Core Challenge

How do we combine two prompts in a way that:
1. Preserves semantic coherence (offspring makes sense)
2. Inherits complementary strengths from both parents
3. Doesn't create contradictions or redundancy
4. Maintains valid prompt structure
5. Produces diverse offspring from the same parents

### Technical Challenges

1. **Segmentation**: How to divide prompts into meaningful, modular components?
2. **Compatibility**: How to determine if segments from different prompts can be combined?
3. **Blending**: How to merge overlapping sections (both have instructions, examples, etc.)?
4. **Coherence**: How to ensure combined prompt flows naturally?
5. **Validation**: How to verify offspring is valid before evaluation?

### Key Questions

- What are the "genes" of a prompt? (instructions, constraints, examples, formatting?)
- How do we identify crossover points? (section boundaries, semantic units?)
- What crossover strategies should we support? (single-point, two-point, uniform, semantic?)
- How do we handle prompts with different structures?
- Should we use the LLM to assist crossover (LMX approach)?

## Solution Overview

### High-Level Approach

We'll implement a **multi-strategy crossover system** that supports:

1. **Prompt Segmentation** (1.4.2.1): Break prompts into modular components
2. **Component Exchange** (1.4.2.2): Swap sections between prompts
3. **Blending** (1.4.2.3): Merge complementary instructions intelligently
4. **Compatibility Checking** (1.4.2.4): Ensure valid combinations

### Architecture

```
lib/jido_ai/runner/gepa/crossover/
  ├── orchestrator.ex              # Main crossover coordinator
  ├── segmenter.ex                 # Prompt segmentation (1.4.2.1)
  ├── exchanger.ex                 # Component exchange (1.4.2.2)
  ├── blender.ex                   # Blending operator (1.4.2.3)
  ├── compatibility_checker.ex     # Compatibility validation (1.4.2.4)
  ├── strategies/
  │   ├── single_point.ex          # Single-point crossover
  │   ├── two_point.ex             # Two-point crossover
  │   ├── uniform.ex               # Uniform crossover
  │   └── semantic.ex              # Semantic/LLM-guided crossover
  └── types.ex                     # Data structures

test/jido_ai/runner/gepa/crossover/
  ├── orchestrator_test.exs
  ├── segmenter_test.exs
  ├── exchanger_test.exs
  ├── blender_test.exs
  ├── compatibility_checker_test.exs
  └── strategies/
      ├── single_point_test.exs
      ├── two_point_test.exs
      ├── uniform_test.exs
      └── semantic_test.exs
```

### Data Flow

```
[Parent Prompt A, Parent Prompt B]
    ↓
Segmenter (analyze structures, identify components)
    ↓ [PromptSegment.t() for each parent]
CompatibilityChecker (verify parents can be crossed)
    ↓ [CompatibilityResult.t()]
Strategy Selection (choose crossover method)
    ↓ [SinglePoint | TwoPoint | Uniform | Semantic]
Exchanger/Blender (perform crossover)
    ↓ [OffspringSegments.t()]
Reconstruction (assemble offspring prompt)
    ↓ [CrossoverResult.t()]
Validation (check semantic coherence)
    ↓
[Offspring Prompt(s)]
```

## Technical Details

### Data Structures

```elixir
defmodule Jido.AI.Runner.GEPA.Crossover do
  use TypedStruct

  @type segment_type :: :instruction | :constraint | :example | :formatting |
                        :reasoning_guide | :task_description | :output_format | :context

  @type crossover_strategy :: :single_point | :two_point | :uniform | :semantic

  @type compatibility_issue :: :incompatible_structure | :contradictory_constraints |
                               :duplicate_content | :semantic_mismatch

  typedstruct module: PromptSegment do
    @moduledoc """
    A modular component of a prompt identified by segmentation.

    Examples:
    - Instruction segment: "Solve this step by step"
    - Constraint segment: "Show all intermediate work"
    - Example segment: "Example: Input: 2+2, Output: 4"
    - Formatting segment: "Format your answer as JSON"
    """

    field(:id, String.t(), enforce: true)
    field(:type, segment_type(), enforce: true)
    field(:content, String.t(), enforce: true)
    field(:start_pos, non_neg_integer(), enforce: true)
    field(:end_pos, non_neg_integer(), enforce: true)
    field(:parent_prompt_id, String.t(), enforce: true)
    field(:priority, :high | :medium | :low, default: :medium)
    field(:metadata, map(), default: %{})
  end

  typedstruct module: SegmentedPrompt do
    @moduledoc """
    A prompt that has been analyzed and broken into segments.
    """

    field(:prompt_id, String.t(), enforce: true)
    field(:raw_text, String.t(), enforce: true)
    field(:segments, list(PromptSegment.t()), default: [])
    field(:structure_type, :simple | :structured | :complex, default: :simple)
    field(:metadata, map(), default: %{})
  end

  typedstruct module: CompatibilityResult do
    @moduledoc """
    Result of checking if two prompts can be crossed.
    """

    field(:compatible, boolean(), enforce: true)
    field(:issues, list(compatibility_issue()), default: [])
    field(:compatibility_score, float(), default: 0.0)  # 0.0-1.0
    field(:recommended_strategy, crossover_strategy() | nil)
    field(:metadata, map(), default: %{})
  end

  typedstruct module: CrossoverConfig do
    @moduledoc """
    Configuration for crossover operation.
    """

    field(:strategy, crossover_strategy(), default: :semantic)
    field(:preserve_sections, list(segment_type()), default: [:task_description])
    field(:min_segment_length, non_neg_integer(), default: 10)
    field(:allow_blending, boolean(), default: true)
    field(:validate_offspring, boolean(), default: true)
    field(:max_offspring, pos_integer(), default: 2)
    field(:metadata, map(), default: %{})
  end

  typedstruct module: CrossoverResult do
    @moduledoc """
    Result of a crossover operation.
    """

    field(:id, String.t(), enforce: true)
    field(:parent_ids, list(String.t()), enforce: true)
    field(:offspring_prompts, list(String.t()), default: [])
    field(:strategy_used, crossover_strategy(), enforce: true)
    field(:segments_exchanged, list(PromptSegment.t()), default: [])
    field(:segments_blended, list(PromptSegment.t()), default: [])
    field(:validated, boolean(), default: false)
    field(:validation_score, float() | nil)
    field(:metadata, map(), default: %{})
  end
end
```

### Module Responsibilities

#### 1. Segmenter (Task 1.4.2.1)

**Purpose**: Identify modular components within prompts.

**Key Functions**:
```elixir
@spec segment(String.t(), keyword()) :: {:ok, SegmentedPrompt.t()} | {:error, term()}
def segment(prompt_text, opts \\ [])

@spec identify_segments(String.t()) :: list(PromptSegment.t())
defp identify_segments(text)

@spec classify_segment(String.t()) :: segment_type()
defp classify_segment(text)

@spec extract_boundaries(String.t()) :: list({non_neg_integer(), non_neg_integer()})
defp extract_boundaries(text)
```

**Segmentation Strategies**:

1. **Structural Segmentation**: Based on markdown headers, blank lines, bullet points
   ```
   # Task Description
   Solve this problem...

   ## Instructions
   1. Show your work
   2. Explain your reasoning

   ## Constraints
   - Use only basic arithmetic
   - No calculators
   ```

2. **Semantic Segmentation**: Based on content type
   - Task description: "Calculate the area..."
   - Instructions: "Follow these steps..."
   - Constraints: "You must..." / "Do not..."
   - Examples: "Example:" / "For instance..."
   - Output format: "Format your answer as..."

3. **Pattern-Based Segmentation**: Using regex/NLP
   - Imperative sentences → instructions
   - Conditional phrases ("if X then Y") → logic rules
   - Questions → task descriptions
   - Code blocks → examples

**Integration with PromptStructure**: Uses existing `PromptStructureAnalyzer` from Task 1.3.3.

#### 2. Exchanger (Task 1.4.2.2)

**Purpose**: Swap segments between parent prompts.

**Key Functions**:
```elixir
@spec exchange_components(SegmentedPrompt.t(), SegmentedPrompt.t(), CrossoverConfig.t()) ::
  {:ok, CrossoverResult.t()} | {:error, term()}
def exchange_components(parent_a, parent_b, config)

@spec single_point_crossover(SegmentedPrompt.t(), SegmentedPrompt.t()) ::
  {:ok, list(String.t())} | {:error, term()}
defp single_point_crossover(parent_a, parent_b)

@spec two_point_crossover(SegmentedPrompt.t(), SegmentedPrompt.t()) ::
  {:ok, list(String.t())} | {:error, term()}
defp two_point_crossover(parent_a, parent_b)

@spec uniform_crossover(SegmentedPrompt.t(), SegmentedPrompt.t()) ::
  {:ok, list(String.t())} | {:error, term()}
defp uniform_crossover(parent_a, parent_b)
```

**Exchange Strategies**:

1. **Single-Point Crossover**:
   ```
   Parent A: [Seg1_A] [Seg2_A] [Seg3_A] [Seg4_A]
   Parent B: [Seg1_B] [Seg2_B] [Seg3_B] [Seg4_B]

   Crossover point after Seg2:

   Offspring 1: [Seg1_A] [Seg2_A] | [Seg3_B] [Seg4_B]
   Offspring 2: [Seg1_B] [Seg2_B] | [Seg3_A] [Seg4_A]
   ```

2. **Two-Point Crossover**:
   ```
   Parent A: [Seg1_A] [Seg2_A] [Seg3_A] [Seg4_A] [Seg5_A]
   Parent B: [Seg1_B] [Seg2_B] [Seg3_B] [Seg4_B] [Seg5_B]

   Crossover points after Seg1 and Seg3:

   Offspring 1: [Seg1_A] | [Seg2_B] [Seg3_B] | [Seg4_A] [Seg5_A]
   Offspring 2: [Seg1_B] | [Seg2_A] [Seg3_A] | [Seg4_B] [Seg5_B]
   ```

3. **Uniform Crossover**:
   ```
   Parent A: [Seg1_A] [Seg2_A] [Seg3_A] [Seg4_A]
   Parent B: [Seg1_B] [Seg2_B] [Seg3_B] [Seg4_B]

   Random selection per segment (50% probability):

   Offspring 1: [Seg1_A] [Seg2_B] [Seg3_A] [Seg4_B]
   Offspring 2: [Seg1_B] [Seg2_A] [Seg3_B] [Seg4_A]
   ```

**Segment Alignment**: When parents have different numbers of segments:
- Match by segment type first (instruction with instruction, constraint with constraint)
- Use null segments for missing types
- Preserve critical segments (e.g., task description always from one parent)

#### 3. Blender (Task 1.4.2.3)

**Purpose**: Merge complementary instructions intelligently.

**Key Functions**:
```elixir
@spec blend_segments(list(PromptSegment.t()), keyword()) ::
  {:ok, PromptSegment.t()} | {:error, term()}
def blend_segments(segments, opts \\ [])

@spec merge_instructions(PromptSegment.t(), PromptSegment.t()) ::
  {:ok, PromptSegment.t()} | {:error, term()}
defp merge_instructions(seg_a, seg_b)

@spec combine_constraints(PromptSegment.t(), PromptSegment.t()) ::
  {:ok, PromptSegment.t()} | {:error, term()}
defp combine_constraints(seg_a, seg_b)

@spec deduplicate_content(list(String.t())) :: list(String.t())
defp deduplicate_content(items)
```

**Blending Strategies**:

1. **Instruction Blending**:
   ```
   Segment A: "Solve this step by step"
   Segment B: "Show your reasoning clearly"

   Blended: "Solve this step by step, showing your reasoning clearly"
   ```

2. **Constraint Combination**:
   ```
   Segment A: "Use only basic arithmetic"
   Segment B: "Explain each calculation"

   Blended (both constraints):
   "Use only basic arithmetic and explain each calculation"
   ```

3. **Example Merging**:
   ```
   Segment A: "Example: 2+2=4"
   Segment B: "Example: 3*5=15"

   Blended (both examples):
   "Examples:
   - 2+2=4
   - 3*5=15"
   ```

4. **Semantic Blending** (LLM-assisted):
   ```
   Segments: [SegA, SegB]

   Prompt to LLM:
   "Combine these two instruction segments into one coherent instruction:
   1. [SegA content]
   2. [SegB content]

   Requirements:
   - Preserve key information from both
   - Remove redundancy
   - Maintain natural flow
   - Keep concise"

   LLM Output: Blended segment
   ```

**Deduplication**: Identify and remove redundant content:
- Exact duplicates: "step by step" appears in both → keep once
- Semantic duplicates: "show your work" ≈ "explain your reasoning" → merge
- Contradictions: "use calculator" vs "no calculators" → flag for compatibility check

#### 4. CompatibilityChecker (Task 1.4.2.4)

**Purpose**: Ensure valid combinations before crossover.

**Key Functions**:
```elixir
@spec check_compatibility(SegmentedPrompt.t(), SegmentedPrompt.t()) ::
  {:ok, CompatibilityResult.t()} | {:error, term()}
def check_compatibility(parent_a, parent_b)

@spec detect_contradictions(list(PromptSegment.t()), list(PromptSegment.t())) ::
  list(compatibility_issue())
defp detect_contradictions(segments_a, segments_b)

@spec calculate_compatibility_score(SegmentedPrompt.t(), SegmentedPrompt.t()) :: float()
defp calculate_compatibility_score(parent_a, parent_b)

@spec recommend_strategy(CompatibilityResult.t()) :: crossover_strategy()
defp recommend_strategy(compatibility)
```

**Compatibility Checks**:

1. **Structure Compatibility**:
   ```elixir
   # Can we align segments meaningfully?
   - Do both have task descriptions? ✓ Good
   - Do segment types overlap? ✓ Good
   - Are structures completely different? ✗ Problematic

   Score based on:
   - Segment type overlap (0.0-1.0)
   - Segment count similarity (0.0-1.0)
   - Overall structure (simple vs complex)
   ```

2. **Semantic Compatibility**:
   ```elixir
   # Do constraints contradict?
   Parent A: "Use only addition"
   Parent B: "Use multiplication"
   → Compatible (different operations, not contradictory)

   Parent A: "Use calculators"
   Parent B: "No calculators allowed"
   → Incompatible (direct contradiction)

   Parent A: "Format as JSON"
   Parent B: "Format as CSV"
   → Incompatible (contradictory output formats)
   ```

3. **Content Duplication**:
   ```elixir
   # Is there too much overlap?
   Parent A and B share 90% of content
   → Low value crossover (offspring very similar to parents)

   Parent A and B share 10% of content
   → High value crossover (diverse offspring)
   ```

4. **Validation Criteria**:
   - No contradictory constraints
   - No duplicate instructions (unless merging intentionally)
   - Compatible task domains
   - Similar complexity levels (optional)
   - Sufficient structural overlap

**Compatibility Score Calculation**:
```elixir
def calculate_compatibility_score(parent_a, parent_b) do
  segment_overlap = calculate_segment_type_overlap(parent_a, parent_b)     # 0.0-1.0
  contradiction_penalty = detect_contradictions_penalty(parent_a, parent_b) # 0.0-1.0
  diversity_bonus = calculate_content_diversity(parent_a, parent_b)        # 0.0-1.0

  # Weighted combination
  base_score = (segment_overlap * 0.4) + (diversity_bonus * 0.4)
  final_score = base_score * (1.0 - contradiction_penalty * 0.6)

  max(0.0, min(1.0, final_score))
end

# Recommended strategies based on compatibility:
# 0.8-1.0: Any strategy (highly compatible)
# 0.6-0.8: Semantic or uniform (moderately compatible)
# 0.4-0.6: Blending only (low compatibility, merge carefully)
# 0.0-0.4: Skip crossover (incompatible)
```

### Integration with Existing Infrastructure

#### Using PromptStructure from Task 1.3.3

```elixir
# Task 1.3.3 already provides PromptStructure:
%PromptStructure{
  raw_text: "...",
  sections: [...],
  has_examples: true/false,
  has_constraints: true/false,
  has_cot_trigger: true/false,
  complexity: :simple | :moderate | :complex,
  patterns: %{}
}

# Crossover Segmenter extends this:
def segment(prompt_text, opts) do
  # 1. Use PromptStructureAnalyzer (from 1.3.3)
  {:ok, structure} = PromptStructureAnalyzer.analyze(prompt_text)

  # 2. Convert sections to segments
  segments = structure.sections
    |> Enum.map(&section_to_segment/1)
    |> classify_segment_types(structure)

  {:ok, %SegmentedPrompt{
    prompt_id: generate_id(),
    raw_text: prompt_text,
    segments: segments,
    structure_type: structure.complexity
  }}
end
```

#### Using Mutation Operators from Task 1.4.1

Crossover produces offspring prompts, which may then need refinement:

```elixir
# After crossover:
{:ok, crossover_result} = Crossover.perform(parent_a, parent_b)

# Offspring might need mutation for polish:
offspring_prompts = crossover_result.offspring_prompts

Enum.map(offspring_prompts, fn offspring ->
  # Apply small mutations to fix formatting, redundancy, etc.
  Mutation.apply_polish_mutations(offspring)
end)
```

#### Dependencies

```elixir
# Uses from Task 1.3.3:
alias Jido.AI.Runner.GEPA.SuggestionGeneration.{
  PromptStructure,
  PromptStructureAnalyzer
}

# Uses from Task 1.4.1:
alias Jido.AI.Runner.GEPA.Mutation.{
  TextOperations,  # For text manipulation utilities
  Validator        # For validating offspring prompts
}
```

## Implementation Plan

### Phase 1: Foundation (1-2 days)

**Goal**: Set up data structures and basic segmentation.

#### Tasks:
1. Create `lib/jido_ai/runner/gepa/crossover/types.ex`
   - Define all TypedStruct modules (PromptSegment, SegmentedPrompt, etc.)
   - Export types for use by other modules

2. Create `lib/jido_ai/runner/gepa/crossover/segmenter.ex`
   - Implement structural segmentation (markdown, blank lines)
   - Implement semantic segmentation (content classification)
   - Integration with PromptStructureAnalyzer

3. Create tests:
   - `test/jido_ai/runner/gepa/crossover/segmenter_test.exs`
   - Test segmentation accuracy on various prompt formats
   - Test segment classification

**Success Criteria**:
- Can segment prompts into meaningful components
- Segment classification >80% accurate
- All tests passing

### Phase 2: Compatibility Checking (1 day)

**Goal**: Validate that prompts can be crossed safely.

#### Tasks:
1. Create `lib/jido_ai/runner/gepa/crossover/compatibility_checker.ex`
   - Implement structure compatibility checks
   - Implement semantic contradiction detection
   - Implement compatibility scoring
   - Implement strategy recommendation

2. Create tests:
   - `test/jido_ai/runner/gepa/crossover/compatibility_checker_test.exs`
   - Test contradiction detection
   - Test compatibility scoring
   - Test strategy recommendation

**Success Criteria**:
- Detects obvious contradictions ("use X" vs "don't use X")
- Compatibility scores correlate with manual assessment
- Recommends appropriate strategies
- All tests passing

### Phase 3: Exchange Strategies (2-3 days)

**Goal**: Implement core crossover strategies.

#### Tasks:
1. Create `lib/jido_ai/runner/gepa/crossover/strategies/single_point.ex`
   - Single-point crossover implementation
   - Segment alignment for different-sized parents

2. Create `lib/jido_ai/runner/gepa/crossover/strategies/two_point.ex`
   - Two-point crossover implementation

3. Create `lib/jido_ai/runner/gepa/crossover/strategies/uniform.ex`
   - Uniform crossover with configurable probability

4. Create `lib/jido_ai/runner/gepa/crossover/exchanger.ex`
   - Orchestrate strategy execution
   - Reconstruct prompts from exchanged segments

5. Create tests for each strategy:
   - `test/jido_ai/runner/gepa/crossover/strategies/single_point_test.exs`
   - `test/jido_ai/runner/gepa/crossover/strategies/two_point_test.exs`
   - `test/jido_ai/runner/gepa/crossover/strategies/uniform_test.exs`
   - `test/jido_ai/runner/gepa/crossover/exchanger_test.exs`

**Success Criteria**:
- All three strategies produce valid offspring
- Offspring inherit segments from both parents as expected
- Segment boundaries preserved
- All tests passing

### Phase 4: Blending Operator (2 days)

**Goal**: Implement intelligent segment merging.

#### Tasks:
1. Create `lib/jido_ai/runner/gepa/crossover/blender.ex`
   - Instruction blending (combine similar segments)
   - Constraint combination (merge non-contradictory constraints)
   - Example merging (collect examples from both)
   - Deduplication logic

2. Create `lib/jido_ai/runner/gepa/crossover/strategies/semantic.ex`
   - LLM-assisted blending (optional, can be Phase 5)
   - Semantic merging of overlapping segments

3. Create tests:
   - `test/jido_ai/runner/gepa/crossover/blender_test.exs`
   - `test/jido_ai/runner/gepa/crossover/strategies/semantic_test.exs`
   - Test instruction blending
   - Test constraint combination
   - Test deduplication

**Success Criteria**:
- Blended segments preserve information from both sources
- No contradictory content in blended output
- Deduplication removes exact and semantic duplicates
- All tests passing

### Phase 5: Orchestration & Validation (1-2 days)

**Goal**: Tie everything together with main orchestrator.

#### Tasks:
1. Create `lib/jido_ai/runner/gepa/crossover/orchestrator.ex`
   - Main `perform/3` function
   - Strategy selection logic
   - Offspring validation
   - Result assembly

2. Create tests:
   - `test/jido_ai/runner/gepa/crossover/orchestrator_test.exs`
   - End-to-end crossover tests
   - Test all strategies via orchestrator
   - Test validation and error handling

3. Integration testing with existing modules:
   - Test with PromptStructureAnalyzer
   - Test with Mutation operators (polish after crossover)

**Success Criteria**:
- Can perform crossover end-to-end
- Validates offspring before returning
- Handles errors gracefully
- All integration tests passing

### Phase 6: Documentation & Examples (1 day)

**Goal**: Comprehensive documentation and usage examples.

#### Tasks:
1. Add module documentation to all modules
2. Create usage examples in module docs
3. Create `CROSSOVER.md` guide with:
   - When to use each strategy
   - How to configure crossover
   - Examples of good vs bad crossover results
   - Integration with GEPA optimization loop

4. Update main GEPA documentation to include crossover

**Success Criteria**:
- All modules have @moduledoc and function @doc
- Examples demonstrate all strategies
- Clear guidance on strategy selection
- Documentation builds without warnings

## Success Criteria

### Functional Requirements

1. **Segmentation (1.4.2.1)**:
   - ✓ Can segment prompts into modular components
   - ✓ Identifies at least 5 segment types (instruction, constraint, example, etc.)
   - ✓ Segment classification >80% accurate
   - ✓ Works with simple, structured, and complex prompts

2. **Exchange (1.4.2.2)**:
   - ✓ Implements single-point, two-point, and uniform crossover
   - ✓ Produces 1-2 offspring from two parents
   - ✓ Offspring contain segments from both parents
   - ✓ Preserves segment boundaries and types

3. **Blending (1.4.2.3)**:
   - ✓ Can merge similar segments intelligently
   - ✓ Combines constraints without contradiction
   - ✓ Deduplicates redundant content
   - ✓ Optional LLM-assisted semantic blending

4. **Compatibility (1.4.2.4)**:
   - ✓ Detects contradictory constraints
   - ✓ Identifies incompatible structures
   - ✓ Calculates compatibility score (0.0-1.0)
   - ✓ Recommends appropriate strategies

### Quality Requirements

1. **Correctness**:
   - ✓ All strategies produce semantically valid offspring
   - ✓ No contradictions in offspring prompts
   - ✓ No information loss from parents (unless intentional)

2. **Diversity**:
   - ✓ Offspring differ from both parents
   - ✓ Different strategies produce different offspring
   - ✓ Uniform crossover more diverse than single-point

3. **Performance**:
   - ✓ Segmentation < 100ms for typical prompt
   - ✓ Crossover < 200ms (excluding LLM calls)
   - ✓ Scales to prompts up to 5000 characters

4. **Testability**:
   - ✓ >90% code coverage
   - ✓ All public functions tested
   - ✓ Integration tests with real prompt examples
   - ✓ Property-based tests for crossover invariants

### Integration Requirements

1. **Uses Task 1.3.3 Infrastructure**:
   - ✓ Leverages PromptStructureAnalyzer
   - ✓ Compatible with PromptStructure data type

2. **Works with Task 1.4.1 Mutations**:
   - ✓ Offspring can be further mutated
   - ✓ Uses TextOperations utilities
   - ✓ Uses Validator for validation

3. **Ready for Task 1.5 Integration**:
   - ✓ Clear API for optimizer to call
   - ✓ Returns structured CrossoverResult
   - ✓ Configurable via CrossoverConfig

## Testing Strategy

### Unit Tests

Each module should have comprehensive unit tests:

1. **Segmenter Tests**:
   - Test structural segmentation (markdown, bullets, blank lines)
   - Test semantic classification (instructions, constraints, examples)
   - Test boundary extraction
   - Test edge cases (empty prompt, single segment, no structure)

2. **CompatibilityChecker Tests**:
   - Test contradiction detection
   - Test structural compatibility
   - Test content duplication detection
   - Test compatibility scoring
   - Test strategy recommendation

3. **Strategy Tests** (for each: single-point, two-point, uniform, semantic):
   - Test basic crossover (equal-sized parents)
   - Test crossover with different-sized parents
   - Test segment alignment
   - Test offspring count
   - Test parent content preservation

4. **Blender Tests**:
   - Test instruction blending
   - Test constraint combination
   - Test example merging
   - Test deduplication (exact and semantic)
   - Test contradiction avoidance

5. **Orchestrator Tests**:
   - Test end-to-end crossover
   - Test strategy selection
   - Test validation
   - Test error handling

### Integration Tests

Test crossover in realistic scenarios:

1. **Cross-Domain Prompts**:
   ```elixir
   # Math prompt + Code prompt
   parent_a = "Solve this algebra problem step by step"
   parent_b = "Write Python code to calculate the result"

   # Should produce offspring combining reasoning + code
   ```

2. **Different Structures**:
   ```elixir
   # Simple prompt + Complex structured prompt
   parent_a = "Calculate the area"
   parent_b = """
   # Task
   Calculate geometric areas

   ## Instructions
   1. Identify the shape
   2. Apply formula

   ## Constraints
   - Use metric units
   """

   # Should align segments intelligently
   ```

3. **With Mutation Pipeline**:
   ```elixir
   # Crossover then mutation
   {:ok, crossover_result} = Crossover.perform(parent_a, parent_b)
   offspring = hd(crossover_result.offspring_prompts)

   {:ok, mutated} = Mutation.apply(offspring, edit_plan)

   # Should work seamlessly
   ```

### Property-Based Tests

Use StreamData for property-based testing:

```elixir
property "crossover always produces valid prompts" do
  check all parent_a <- prompt_generator(),
            parent_b <- prompt_generator(),
            compatible?(parent_a, parent_b) do
    {:ok, result} = Crossover.perform(parent_a, parent_b)

    # Offspring should be valid prompts
    assert Enum.all?(result.offspring_prompts, &valid_prompt?/1)

    # Offspring should contain content from both parents
    assert has_content_from_both_parents?(result.offspring_prompts, parent_a, parent_b)
  end
end

property "offspring differ from parents" do
  check all parent_a <- distinct_prompt_generator(),
            parent_b <- distinct_prompt_generator() do
    {:ok, result} = Crossover.perform(parent_a, parent_b)

    # Offspring should not be identical to either parent
    assert Enum.all?(result.offspring_prompts, fn offspring ->
      offspring != parent_a.raw_text and offspring != parent_b.raw_text
    end)
  end
end

property "uniform crossover more diverse than single-point" do
  check all parent_a <- prompt_generator(),
            parent_b <- prompt_generator() do
    {:ok, uniform_result} = Crossover.perform(parent_a, parent_b, strategy: :uniform)
    {:ok, single_result} = Crossover.perform(parent_a, parent_b, strategy: :single_point)

    uniform_diversity = measure_diversity(uniform_result.offspring_prompts, [parent_a, parent_b])
    single_diversity = measure_diversity(single_result.offspring_prompts, [parent_a, parent_b])

    # Uniform should generally be more diverse
    assert uniform_diversity >= single_diversity
  end
end
```

### Test Fixtures

Create realistic test prompts:

```elixir
# test/support/crossover_test_fixtures.ex

defmodule Jido.AI.Runner.GEPA.CrossoverTestFixtures do
  def math_prompt_simple do
    "Solve this math problem step by step."
  end

  def math_prompt_structured do
    """
    # Math Problem Solver

    ## Task
    Solve the given mathematical problem.

    ## Instructions
    1. Show all steps clearly
    2. Explain your reasoning
    3. Verify your answer

    ## Constraints
    - Use only basic arithmetic
    - Show intermediate calculations

    ## Output Format
    Provide the final answer as a number.
    """
  end

  def code_prompt_structured do
    """
    # Code Generation Task

    ## Instructions
    - Write clean, readable code
    - Include comments
    - Handle edge cases

    ## Constraints
    - Use Python 3
    - No external libraries

    ## Example
    Input: [1, 2, 3]
    Output: 6
    """
  end

  def incompatible_prompts do
    {
      "Format output as JSON",
      "Format output as CSV"
    }
  end

  def compatible_prompts do
    {
      "Solve step by step with clear explanations",
      "Show all intermediate work and verify results"
    }
  end
end
```

## Risks & Considerations

### Technical Risks

1. **Semantic Incoherence**:
   - **Risk**: Offspring prompts don't make sense semantically
   - **Mitigation**:
     - Strong compatibility checking before crossover
     - Validation after crossover
     - Blending for smooth transitions
     - Fall back to mutation if crossover fails

2. **Segment Misalignment**:
   - **Risk**: Can't align segments from different parent structures
   - **Mitigation**:
     - Multiple alignment strategies (type-based, position-based, semantic)
     - Allow null segments for missing types
     - Skip crossover if alignment quality too low

3. **Loss of Critical Information**:
   - **Risk**: Crossover removes essential task information
   - **Mitigation**:
     - Preserve critical segments (task description always from one parent)
     - Validate offspring has all required components
     - ConfigurableConfig.preserve_sections list

4. **Performance with Large Prompts**:
   - **Risk**: Segmentation and compatibility checking slow for large prompts
   - **Mitigation**:
     - Cache PromptStructure analysis
     - Limit prompt size for crossover (e.g., max 5000 chars)
     - Optimize text operations

### Design Risks

1. **Overly Complex Segmentation**:
   - **Risk**: Too many segment types, hard to maintain
   - **Mitigation**:
     - Start with 6-8 core types
     - Use :other for edge cases
     - Extensible design for adding types later

2. **Strategy Selection Ambiguity**:
   - **Risk**: Unclear when to use which strategy
   - **Mitigation**:
     - Clear documentation with examples
     - Compatibility checker recommends strategy
     - Default to semantic (safest)

3. **LLM Dependency for Blending**:
   - **Risk**: Semantic blending requires LLM, slows crossover
   - **Mitigation**:
     - Make LLM blending optional
     - Rule-based blending as default
     - Only use LLM for complex merges

### Integration Risks

1. **Interaction with Mutations**:
   - **Risk**: Crossover + mutation might create instability
   - **Mitigation**:
     - Test crossover → mutation pipeline
     - Mutation can "polish" crossover results
     - Both use same validation

2. **Diversity vs Quality Tradeoff**:
   - **Risk**: Crossover creates diverse but low-quality offspring
   - **Mitigation**:
     - Compatibility checking filters bad crosses
     - Evaluation will select quality offspring
     - Balance crossover rate with mutation rate

## Open Questions

1. **LLM-Assisted Crossover**: Should we implement LMX (Language Model Crossover) where the LLM generates offspring from parent prompts?
   - **Pros**: Highly semantic, respects language structure
   - **Cons**: Slower, requires LLM calls, less predictable
   - **Decision**: Implement as optional semantic strategy in Phase 4

2. **Multi-Parent Crossover**: Support crossover from 3+ parents?
   - **Pros**: More diversity, can combine traits from multiple high-performers
   - **Cons**: More complex, harder to validate
   - **Decision**: Start with 2-parent, extend later if needed

3. **Adaptive Crossover**: Should crossover strategies adapt based on population diversity?
   - **Pros**: More uniform when diverse, more single-point when converged
   - **Cons**: Adds complexity
   - **Decision**: Defer to Task 1.4.4 (Mutation Rate Adaptation)

4. **Segment Weighting**: Should segments have different importance weights?
   - **Pros**: Preserve more important segments (task description > formatting)
   - **Cons**: How to determine weights?
   - **Decision**: Support priority field in PromptSegment, use in strategy selection

## Future Enhancements

Beyond Task 1.4.2 scope, consider for later:

1. **N-Point Crossover**: Generalize to arbitrary N crossover points
2. **Partially Matched Crossover (PMX)**: For ordered segment sequences
3. **Order Crossover (OX)**: Preserve relative segment ordering
4. **Cycle Crossover (CX)**: Maintain segment positions
5. **LMX Variants**: Different prompt templates for LLM-assisted crossover
6. **Learned Segmentation**: ML model to identify optimal segment boundaries
7. **Contextual Blending**: Use task context to guide blending decisions
8. **Multi-Objective Crossover**: Crossover that optimizes for multiple objectives (accuracy + cost + latency)

## Summary

This planning document provides a comprehensive roadmap for implementing GEPA Task 1.4.2: Crossover & Combination Operators. The implementation will:

1. **Segment prompts** into modular components (instructions, constraints, examples, etc.)
2. **Check compatibility** between parent prompts before crossing
3. **Implement multiple strategies**: single-point, two-point, uniform, semantic crossover
4. **Blend segments** intelligently when needed
5. **Validate offspring** to ensure semantic coherence
6. **Integrate seamlessly** with existing GEPA infrastructure

The phased implementation approach ensures steady progress with clear milestones. By the end of this task, GEPA will be able to evolve prompts not just through targeted mutations, but by combining the best traits from multiple high-performing prompts—a critical capability for genetic-style optimization.

**Estimated Timeline**: 8-10 days for full implementation, testing, and documentation.

**Key Dependencies**:
- Task 1.3.3 (Suggestion Generation) - PromptStructureAnalyzer ✓
- Task 1.4.1 (Mutation Operators) - TextOperations, Validator ✓

**Enables**:
- Task 1.4.3 (Diversity Enforcement) - Uses crossover for diversity
- Task 1.5 (Integration Tests) - Complete mutation+crossover pipeline
- Stage 2 (Evolution & Selection) - Pareto optimization with crossover
