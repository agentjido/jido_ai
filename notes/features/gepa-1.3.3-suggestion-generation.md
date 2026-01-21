# GEPA Task 1.3.3: Improvement Suggestion Generation - Feature Planning

## Overview

This document provides comprehensive planning for implementing GEPA Task 1.3.3: Improvement Suggestion Generation. This task bridges the gap between abstract LLM suggestions (Task 1.3.2) and concrete prompt modifications (Task 1.4 Mutation Operators). While the LLM tells us *what* to change and *why*, this task generates the *actual text edits* that will be applied to prompts.

## Status

- **Phase**: 5 (GEPA Optimization)
- **Stage**: 1 (Foundation)
- **Section**: 1.3 (Reflection & Feedback Generation)
- **Task**: 1.3.3 (Improvement Suggestion Generation)
- **Status**: Planning
- **Branch**: TBD (suggest: `feature/gepa-1.3.3-suggestion-generation`)

## Prerequisites Completed

### Task 1.3.1: Trajectory Analysis ✅
- TrajectoryAnalyzer module with failure point identification
- Reasoning step analysis (contradiction, circular reasoning detection)
- Success pattern extraction
- Comparative analysis capabilities
- 40 passing tests

### Task 1.3.2: LLM-Guided Reflection ✅
- Reflector module orchestrating LLM reflection calls
- PromptBuilder creating structured reflection prompts
- SuggestionParser extracting structured suggestions from LLM responses
- Suggestion struct with: type (add/modify/remove/restructure), category (clarity/constraint/example/structure/reasoning), description, rationale, priority, specific_text, target_section
- Multi-turn conversation support (ConversationManager stub)

## Context & Motivation

### The Critical Distinction

**Task 1.3.2 (Reflector)** gets suggestions FROM the LLM:
- "Add clearer instructions about step-by-step reasoning"
- "Include constraints about showing intermediate work"
- "Remove redundant preamble"

**Task 1.3.3 (SuggestionGenerator)** converts those into concrete edits:
- Identifies WHERE in the prompt to make the change
- Generates the ACTUAL TEXT to insert/modify/remove
- Validates the edit is applicable to the prompt structure
- Handles conflicts between multiple suggestions
- Ranks edits by expected impact

### Why This Task Matters

The LLM's suggestions are conceptual and abstract. To actually evolve prompts, we need:

1. **Concrete Text Modifications**: Exact strings to insert, replace, or delete
2. **Location Identification**: Where in the prompt each change applies
3. **Conflict Resolution**: What to do when suggestions contradict
4. **Applicability Validation**: Ensuring edits make sense for the prompt structure
5. **Priority Ordering**: Which edits to apply first when resources are limited

Without this layer, mutation operators would have to interpret vague suggestions, leading to inconsistent or ineffective prompt modifications.

### GEPA's Evolutionary Pipeline

```
TrajectoryAnalyzer (1.3.1)
    ↓ [trajectory analysis]
Reflector (1.3.2)
    ↓ [abstract suggestions: "add X", "clarify Y"]
SuggestionGenerator (1.3.3) ← THIS TASK
    ↓ [concrete edits: insert "text" at position P]
Mutation Operators (1.4)
    ↓ [modified prompts]
Evaluation & Selection
```

## Architecture Overview

### Module Structure

```
lib/jido/runner/gepa/suggestion_generator.ex       # Main orchestration
lib/jido/runner/gepa/suggestion_generation/
  ├── edit_builder.ex                               # Converts suggestions to edits
  ├── location_analyzer.ex                          # Identifies where to apply edits
  ├── edit_validator.ex                             # Validates edit applicability
  ├── conflict_resolver.ex                          # Handles conflicting suggestions
  ├── impact_ranker.ex                              # Ranks edits by expected impact
  └── prompt_structure_analyzer.ex                  # Analyzes prompt organization

test/jido/runner/gepa/suggestion_generator_test.exs
test/jido/runner/gepa/suggestion_generation/
  ├── edit_builder_test.exs
  ├── location_analyzer_test.exs
  ├── edit_validator_test.exs
  ├── conflict_resolver_test.exs
  ├── impact_ranker_test.exs
  └── prompt_structure_analyzer_test.exs
```

### Data Flow

```
ParsedReflection (from Task 1.3.2)
  [suggestions: list(Suggestion.t())]
  [original_prompt: string]
    ↓
PromptStructureAnalyzer (analyze prompt organization)
    ↓
LocationAnalyzer (identify where each suggestion applies)
    ↓
EditBuilder (generate concrete edit operations)
    ↓
EditValidator (check applicability and safety)
    ↓
ConflictResolver (resolve conflicting edits)
    ↓
ImpactRanker (rank by expected effectiveness)
    ↓
GeneratedEditPlan
  [edits: list(PromptEdit.t())]
  [ranked: boolean]
  [validated: boolean]
    ↓
[To Mutation Operators in Task 1.4]
```

## Task Breakdown

### Task 1.3.3.1: Concrete Prompt Edit Generation

**Goal**: Convert abstract suggestions into concrete, actionable prompt modifications.

#### Edit Types

1. **Addition Edits**: Insert new text
   - Append to end
   - Prepend to beginning
   - Insert at section boundary
   - Insert inline (e.g., within a sentence)

2. **Modification Edits**: Change existing text
   - Replace word/phrase
   - Rephrase sentence/paragraph
   - Strengthen/weaken language
   - Add qualifiers or constraints

3. **Deletion Edits**: Remove text
   - Remove word/phrase
   - Delete sentence/paragraph
   - Remove redundant sections
   - Strip unnecessary preamble

4. **Restructure Edits**: Reorganize content
   - Reorder sections
   - Move content between sections
   - Split complex instructions
   - Merge related instructions

#### Data Structures

```elixir
defmodule Jido.Runner.GEPA.SuggestionGeneration do
  use TypedStruct

  @type edit_operation :: :insert | :replace | :delete | :move
  @type edit_scope :: :word | :phrase | :sentence | :paragraph | :section | :prompt
  @type location_type :: :start | :end | :before | :after | :within | :replace_all

  typedstruct module: PromptLocation do
    @moduledoc """
    Identifies a specific location within a prompt.

    Can represent:
    - Absolute position (character offset)
    - Relative position (before/after marker)
    - Section-based (within a named section)
    - Pattern-based (matching regex/text)
    """

    field(:type, location_type(), enforce: true)
    field(:absolute_position, non_neg_integer() | nil)
    field(:relative_marker, String.t() | nil)
    field(:section_name, String.t() | nil)
    field(:pattern, String.t() | Regex.t() | nil)
    field(:scope, edit_scope(), default: :phrase)
    field(:confidence, float(), default: 1.0)
  end

  typedstruct module: PromptEdit do
    @moduledoc """
    A concrete edit operation to apply to a prompt.

    Represents the actual text modification that mutation operators
    will perform, with all details specified.
    """

    field(:id, String.t(), enforce: true)
    field(:operation, edit_operation(), enforce: true)
    field(:location, PromptLocation.t(), enforce: true)
    field(:content, String.t() | nil)  # Text to insert/replace
    field(:target_text, String.t() | nil)  # Text being replaced/deleted
    field(:source_suggestion, Reflector.Suggestion.t(), enforce: true)
    field(:rationale, String.t(), enforce: true)
    field(:impact_score, float(), default: 0.5)
    field(:priority, :high | :medium | :low, default: :medium)
    field(:validated, boolean(), default: false)
    field(:conflicts_with, list(String.t()), default: [])
    field(:depends_on, list(String.t()), default: [])
    field(:metadata, map(), default: %{})
  end

  typedstruct module: PromptStructure do
    @moduledoc """
    Analyzed structure of a prompt.

    Identifies sections, patterns, and organizational elements
    that inform where edits can be applied.
    """

    field(:raw_text, String.t(), enforce: true)
    field(:sections, list(map()), default: [])
    field(:has_examples, boolean(), default: false)
    field(:has_constraints, boolean(), default: false)
    field(:has_cot_trigger, boolean(), default: false)
    field(:length, non_neg_integer(), enforce: true)
    field(:complexity, :simple | :moderate | :complex, default: :moderate)
    field(:patterns, map(), default: %{})
    field(:metadata, map(), default: %{})
  end

  typedstruct module: EditPlan do
    @moduledoc """
    Complete plan of edits to apply to a prompt.

    Contains all validated, ranked edits ready for mutation operators.
    Includes conflict resolution and dependency ordering.
    """

    field(:id, String.t(), enforce: true)
    field(:original_prompt, String.t(), enforce: true)
    field(:prompt_structure, PromptStructure.t(), enforce: true)
    field(:edits, list(PromptEdit.t()), default: [])
    field(:total_edits, non_neg_integer(), default: 0)
    field(:high_impact_edits, non_neg_integer(), default: 0)
    field(:conflicts_resolved, non_neg_integer(), default: 0)
    field(:validated, boolean(), default: false)
    field(:ranked, boolean(), default: false)
    field(:metadata, map(), default: %{})
  end

  typedstruct module: ConflictGroup do
    @moduledoc """
    Group of conflicting edits that cannot all be applied.

    Requires resolution strategy to select which edits to keep.
    """

    field(:edits, list(PromptEdit.t()), enforce: true)
    field(:conflict_type, :overlapping | :contradictory | :dependent, enforce: true)
    field(:resolution_strategy, atom(), default: :highest_impact)
    field(:resolved, boolean(), default: false)
    field(:selected_edit, PromptEdit.t() | nil)
  end
end
```

#### Implementation - EditBuilder

```elixir
defmodule Jido.Runner.GEPA.SuggestionGeneration.EditBuilder do
  @moduledoc """
  Converts abstract suggestions into concrete edit operations.

  Takes a Suggestion from the Reflector and generates specific
  PromptEdit operations with exact text and locations.
  """

  alias Jido.Runner.GEPA.Reflector.Suggestion
  alias Jido.Runner.GEPA.SuggestionGeneration.{PromptEdit, PromptLocation, PromptStructure}

  @doc """
  Builds concrete edits from a suggestion.

  ## Parameters

  - `suggestion` - Abstract suggestion from LLM reflection
  - `prompt_structure` - Analyzed prompt structure
  - `opts` - Options:
    - `:max_edits_per_suggestion` - Limit edits generated (default: 3)
    - `:require_specific_text` - Only generate if specific_text present (default: false)

  ## Returns

  - `{:ok, [PromptEdit.t()]}` - List of concrete edits
  - `{:error, reason}` - If edit generation fails
  """
  def build_edits(%Suggestion{} = suggestion, %PromptStructure{} = structure, opts \\ []) do
    case suggestion.type do
      :add -> build_addition_edits(suggestion, structure, opts)
      :modify -> build_modification_edits(suggestion, structure, opts)
      :remove -> build_deletion_edits(suggestion, structure, opts)
      :restructure -> build_restructure_edits(suggestion, structure, opts)
    end
  end

  defp build_addition_edits(suggestion, structure, opts) do
    # Determine where to add content
    location = identify_addition_location(suggestion, structure)

    # Generate content to add (from specific_text or generate from description)
    content = generate_addition_content(suggestion, structure)

    # Create edit
    edit = %PromptEdit{
      id: generate_edit_id(),
      operation: :insert,
      location: location,
      content: content,
      source_suggestion: suggestion,
      rationale: suggestion.rationale,
      priority: suggestion.priority,
      metadata: %{
        category: suggestion.category,
        target_section: suggestion.target_section
      }
    }

    {:ok, [edit]}
  end

  defp build_modification_edits(suggestion, structure, opts) do
    # Identify what text to modify
    target_text = identify_target_text(suggestion, structure)

    # Generate replacement text
    replacement = generate_replacement_content(suggestion, structure, target_text)

    # Create edit
    edit = %PromptEdit{
      id: generate_edit_id(),
      operation: :replace,
      location: %PromptLocation{
        type: :within,
        pattern: target_text,
        scope: :phrase
      },
      content: replacement,
      target_text: target_text,
      source_suggestion: suggestion,
      rationale: suggestion.rationale,
      priority: suggestion.priority
    }

    {:ok, [edit]}
  end

  defp build_deletion_edits(suggestion, structure, opts) do
    # Identify what to remove
    target_text = identify_removal_target(suggestion, structure)

    edit = %PromptEdit{
      id: generate_edit_id(),
      operation: :delete,
      location: %PromptLocation{
        type: :within,
        pattern: target_text,
        scope: :phrase
      },
      target_text: target_text,
      source_suggestion: suggestion,
      rationale: suggestion.rationale,
      priority: suggestion.priority
    }

    {:ok, [edit]}
  end

  defp build_restructure_edits(suggestion, structure, opts) do
    # Identify sections to reorganize
    # May generate multiple move operations
    {:ok, []}  # Complex implementation
  end

  defp identify_addition_location(suggestion, structure) do
    cond do
      # Use target_section if provided
      suggestion.target_section ->
        %PromptLocation{
          type: :within,
          section_name: suggestion.target_section,
          scope: :section
        }

      # Add constraints section if suggestion is constraint
      suggestion.category == :constraint and not structure.has_constraints ->
        %PromptLocation{
          type: :after,
          relative_marker: find_intro_section(structure),
          scope: :section
        }

      # Add examples section if suggestion is example
      suggestion.category == :example and not structure.has_examples ->
        %PromptLocation{
          type: :before,
          relative_marker: find_closing_section(structure),
          scope: :section
        }

      # Add CoT trigger if reasoning suggestion and missing
      suggestion.category == :reasoning and not structure.has_cot_trigger ->
        %PromptLocation{
          type: :end,
          scope: :prompt
        }

      # Default: append to end
      true ->
        %PromptLocation{
          type: :end,
          scope: :prompt
        }
    end
  end

  defp generate_addition_content(suggestion, structure) do
    # Use specific_text if provided
    if suggestion.specific_text do
      format_addition_text(suggestion.specific_text, suggestion.category)
    else
      # Generate from description
      generate_text_from_description(suggestion.description, suggestion.category)
    end
  end

  defp format_addition_text(text, category) do
    case category do
      :constraint -> "\n\nConstraints:\n- #{text}"
      :example -> "\n\nExample:\n#{text}"
      :reasoning -> "\n\n#{text}"
      :structure -> "\n#{text}"
      _ -> "\n#{text}"
    end
  end

  defp generate_text_from_description(description, category) do
    # Basic text generation based on description
    # In production, could use LLM to expand description into concrete text
    case category do
      :constraint -> "\n\nConstraint: #{description}"
      :example -> "\n\nNote: #{description}"
      _ -> "\n#{description}"
    end
  end

  defp identify_target_text(suggestion, structure) do
    # Use specific_text or target_section to find text
    suggestion.target_section || extract_relevant_section(suggestion, structure)
  end

  defp identify_removal_target(suggestion, structure) do
    # Find text matching suggestion description
    suggestion.specific_text || find_matching_content(suggestion.description, structure)
  end

  defp generate_edit_id do
    "edit_#{:erlang.unique_integer([:positive])}"
  end

  # Additional helper functions...
end
```

#### Implementation Checklist

- [ ] Create `SuggestionGeneration.EditBuilder` module
- [ ] Implement `build_edits/3` main function
- [ ] Add type-specific edit builders:
  - [ ] `build_addition_edits/3`
  - [ ] `build_modification_edits/3`
  - [ ] `build_deletion_edits/3`
  - [ ] `build_restructure_edits/3`
- [ ] Implement location identification
  - [ ] `identify_addition_location/2`
  - [ ] `identify_modification_target/2`
  - [ ] `identify_removal_target/2`
- [ ] Implement content generation
  - [ ] `generate_addition_content/2`
  - [ ] `generate_replacement_content/3`
  - [ ] `format_addition_text/2`
- [ ] Support category-specific formatting
- [ ] Handle missing specific_text gracefully
- [ ] Unit tests for edit building (25+ tests)

---

### Task 1.3.3.2: Suggestion Categorization

**Goal**: Categorize suggestions to inform edit generation strategies and prioritization.

The Reflector already categorizes suggestions (Task 1.3.2), but we need to use those categories to:

1. **Guide Edit Generation**: Different categories need different edit strategies
2. **Inform Location Selection**: Where edits naturally fit in prompt structure
3. **Support Conflict Resolution**: Some categories can coexist, others conflict
4. **Enable Impact Estimation**: Some categories typically have higher impact

#### Category Mapping to Edit Strategies

```elixir
defmodule Jido.Runner.GEPA.SuggestionGeneration.CategoryStrategy do
  @moduledoc """
  Maps suggestion categories to edit generation strategies.
  """

  @category_strategies %{
    clarity: %{
      preferred_operation: :modify,
      typical_location: :existing_content,
      impact_multiplier: 1.2,
      conflicts_with: [],
      examples: [
        "Rephrase vague instructions",
        "Add specific definitions",
        "Clarify ambiguous terms"
      ]
    },

    constraint: %{
      preferred_operation: :add,
      typical_location: :dedicated_section,
      impact_multiplier: 1.5,
      conflicts_with: [:removal_of_constraints],
      examples: [
        "Add output format requirements",
        "Specify length limits",
        "Define boundary conditions"
      ]
    },

    example: %{
      preferred_operation: :add,
      typical_location: :after_instructions,
      impact_multiplier: 1.3,
      conflicts_with: [:too_many_examples],
      examples: [
        "Add worked example",
        "Show input/output pair",
        "Demonstrate edge case"
      ]
    },

    structure: %{
      preferred_operation: :restructure,
      typical_location: :global,
      impact_multiplier: 1.1,
      conflicts_with: [:other_structure_changes],
      examples: [
        "Reorder sections for clarity",
        "Add section headers",
        "Group related instructions"
      ]
    },

    reasoning: %{
      preferred_operation: :add,
      typical_location: :beginning_or_end,
      impact_multiplier: 1.8,
      conflicts_with: [],
      examples: [
        "Add 'think step by step' trigger",
        "Request intermediate reasoning",
        "Specify thought process format"
      ]
    }
  }

  def get_strategy(category) do
    @category_strategies[category] || default_strategy()
  end

  def preferred_operation(category) do
    get_strategy(category).preferred_operation
  end

  def typical_location(category) do
    get_strategy(category).typical_location
  end

  def impact_multiplier(category) do
    get_strategy(category).impact_multiplier
  end

  def conflicts_with(category) do
    get_strategy(category).conflicts_with
  end

  defp default_strategy do
    %{
      preferred_operation: :modify,
      typical_location: :existing_content,
      impact_multiplier: 1.0,
      conflicts_with: []
    }
  end
end
```

#### Implementation Checklist

- [ ] Create `CategoryStrategy` module
- [ ] Define category-specific strategies
- [ ] Implement strategy lookup
- [ ] Add conflict identification by category
- [ ] Support custom category strategies
- [ ] Unit tests for categorization (15+ tests)

---

### Task 1.3.3.3: Edit Ranking by Expected Impact

**Goal**: Rank generated edits by expected effectiveness to prioritize high-impact modifications.

When we have limited mutation budget or want to apply edits incrementally, we need to know which edits will likely have the biggest positive effect.

#### Impact Factors

```elixir
defmodule Jido.Runner.GEPA.SuggestionGeneration.ImpactRanker do
  @moduledoc """
  Ranks edits by expected impact on prompt performance.

  Uses multiple factors to estimate which edits will most improve
  prompt quality, enabling prioritization when applying changes.
  """

  alias Jido.Runner.GEPA.SuggestionGeneration.{PromptEdit, PromptStructure}

  @doc """
  Ranks a list of edits by expected impact.

  ## Parameters

  - `edits` - List of PromptEdit to rank
  - `structure` - Analyzed prompt structure
  - `trajectory_analysis` - Optional trajectory analysis for context
  - `opts` - Options:
    - `:factors` - Which factors to include (default: all)
    - `:weights` - Custom factor weights

  ## Returns

  - `{:ok, [PromptEdit.t()]}` - Edits sorted by impact score (descending)
  """
  def rank_edits(edits, structure, trajectory_analysis \\ nil, opts \\ []) do
    # Calculate impact score for each edit
    scored_edits =
      edits
      |> Enum.map(&score_edit(&1, structure, trajectory_analysis, opts))
      |> Enum.sort_by(& &1.impact_score, :desc)

    {:ok, scored_edits}
  end

  defp score_edit(edit, structure, trajectory_analysis, opts) do
    factors = [
      base_priority_score(edit),
      category_impact_score(edit),
      specificity_score(edit),
      structural_fit_score(edit, structure),
      failure_alignment_score(edit, trajectory_analysis),
      novelty_score(edit, structure)
    ]

    weights = opts[:weights] || default_weights()

    weighted_score =
      factors
      |> Enum.zip(weights)
      |> Enum.map(fn {score, weight} -> score * weight end)
      |> Enum.sum()
      |> normalize_score()

    %{edit | impact_score: weighted_score}
  end

  # Base score from suggestion priority
  defp base_priority_score(edit) do
    case edit.priority do
      :high -> 1.0
      :medium -> 0.6
      :low -> 0.3
    end
  end

  # Score based on category's typical impact
  defp category_impact_score(edit) do
    category = edit.source_suggestion.category
    CategoryStrategy.impact_multiplier(category) / 2.0
  end

  # Higher score if edit has specific text vs. vague description
  defp specificity_score(edit) do
    if edit.content && String.length(edit.content) > 10 do
      1.0
    else
      0.5
    end
  end

  # Score based on how well edit fits prompt structure
  defp structural_fit_score(edit, structure) do
    case {edit.operation, structure.complexity} do
      {:insert, :simple} -> 0.9  # Easy to add to simple prompts
      {:insert, :complex} -> 0.7  # Harder to find right spot
      {:replace, :simple} -> 0.7  # Simple prompts have less to replace
      {:replace, :complex} -> 0.9  # Complex prompts benefit from refinement
      {:delete, _} -> 0.8  # Deletion generally safe
      {:move, :simple} -> 0.6  # Moving in simple prompt can disrupt
      {:move, :complex} -> 0.8  # Complex prompts benefit from reorganization
      _ -> 0.7
    end
  end

  # Score based on alignment with identified failures
  defp failure_alignment_score(edit, nil), do: 0.5

  defp failure_alignment_score(edit, trajectory_analysis) do
    # Check if edit addresses identified failure points
    suggestion = edit.source_suggestion

    alignment =
      trajectory_analysis.failure_points
      |> Enum.any?(fn fp ->
        failure_matches_suggestion?(fp, suggestion)
      end)

    if alignment, do: 1.0, else: 0.5
  end

  # Score for novelty (avoid redundant edits)
  defp novelty_score(edit, structure) do
    # Check if prompt already has similar content
    if content_already_present?(edit.content, structure.raw_text) do
      0.3
    else
      1.0
    end
  end

  defp default_weights do
    [
      0.25,  # base_priority
      0.20,  # category_impact
      0.15,  # specificity
      0.15,  # structural_fit
      0.20,  # failure_alignment
      0.05   # novelty
    ]
  end

  defp normalize_score(score) do
    # Normalize to 0.0-1.0 range
    max(0.0, min(1.0, score))
  end

  defp failure_matches_suggestion?(failure_point, suggestion) do
    # Check if suggestion addresses the failure
    # This is heuristic-based pattern matching
    failure_desc = String.downcase(failure_point.description)
    suggestion_desc = String.downcase(suggestion.description)

    # Look for keyword overlap
    keywords = extract_keywords(failure_desc)
    Enum.any?(keywords, &String.contains?(suggestion_desc, &1))
  end

  defp content_already_present?(content, prompt) do
    if content do
      # Check for similar content (fuzzy matching)
      similarity = string_similarity(content, prompt)
      similarity > 0.7
    else
      false
    end
  end

  defp extract_keywords(text) do
    text
    |> String.split(~r/\W+/)
    |> Enum.filter(&(String.length(&1) > 4))
    |> Enum.take(5)
  end

  defp string_similarity(str1, str2) do
    # Simple similarity metric
    # In production, use proper string similarity algorithm
    str1_words = String.split(str1) |> MapSet.new()
    str2_words = String.split(str2) |> MapSet.new()

    intersection = MapSet.intersection(str1_words, str2_words)
    union = MapSet.union(str1_words, str2_words)

    MapSet.size(intersection) / max(MapSet.size(union), 1)
  end
end
```

#### Ranking Criteria

1. **Base Priority** (from LLM suggestion)
   - High priority suggestions ranked first
   - LLM's assessment carries significant weight

2. **Category Impact** (empirical effectiveness)
   - Reasoning enhancements typically high impact
   - Constraints usually effective
   - Clarity improvements moderate impact

3. **Specificity** (actionability)
   - Edits with concrete text preferred
   - Vague edits ranked lower

4. **Structural Fit** (compatibility)
   - How well edit integrates with prompt structure
   - Simple vs. complex prompt considerations

5. **Failure Alignment** (relevance)
   - Does edit address identified failure points?
   - Direct alignment with problems scored higher

6. **Novelty** (avoid redundancy)
   - Penalize edits adding content already present
   - Reward genuinely new additions

#### Implementation Checklist

- [ ] Create `ImpactRanker` module
- [ ] Implement `rank_edits/4` main function
- [ ] Add scoring functions for each factor:
  - [ ] `base_priority_score/1`
  - [ ] `category_impact_score/1`
  - [ ] `specificity_score/1`
  - [ ] `structural_fit_score/2`
  - [ ] `failure_alignment_score/2`
  - [ ] `novelty_score/2`
- [ ] Implement weighted scoring with normalization
- [ ] Support custom factor weights
- [ ] Add string similarity for redundancy detection
- [ ] Unit tests for ranking (20+ tests)

---

### Task 1.3.3.4: Edit Validation

**Goal**: Validate that generated edits are applicable, safe, and won't break the prompt.

Before passing edits to mutation operators, we must ensure they:
1. Can actually be applied (target text exists, location is valid)
2. Won't corrupt prompt structure
3. Don't introduce errors or ambiguity
4. Preserve prompt intent
5. Are mutually compatible (or conflicts identified)

#### Validation Rules

```elixir
defmodule Jido.Runner.GEPA.SuggestionGeneration.EditValidator do
  @moduledoc """
  Validates that generated edits are safe and applicable.

  Performs multiple validation passes:
  1. Location validation - Can we find where to apply the edit?
  2. Content validation - Is the edit content well-formed?
  3. Safety validation - Will the edit corrupt the prompt?
  4. Compatibility validation - Do edits conflict?
  5. Intent preservation - Does edit maintain prompt purpose?
  """

  alias Jido.Runner.GEPA.SuggestionGeneration.{PromptEdit, PromptStructure}

  @doc """
  Validates a single edit.

  ## Returns

  - `{:ok, PromptEdit.t()}` - Edit is valid (marked as validated)
  - `{:error, reason}` - Edit validation failed
  """
  def validate_edit(%PromptEdit{} = edit, %PromptStructure{} = structure) do
    with :ok <- validate_location(edit, structure),
         :ok <- validate_content(edit),
         :ok <- validate_safety(edit, structure),
         :ok <- validate_intent(edit, structure) do
      {:ok, %{edit | validated: true}}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Validates a list of edits and identifies conflicts.

  ## Returns

  - `{:ok, {valid_edits, conflicts}}` - Valid edits and conflict groups
  """
  def validate_edit_list(edits, structure) do
    # Validate each edit individually
    validation_results =
      edits
      |> Enum.map(&{&1, validate_edit(&1, structure)})

    valid_edits =
      validation_results
      |> Enum.filter(&match?({_, {:ok, _}}, &1))
      |> Enum.map(fn {_, {:ok, edit}} -> edit end)

    # Identify conflicts among valid edits
    conflicts = identify_conflicts(valid_edits, structure)

    {:ok, {valid_edits, conflicts}}
  end

  # Validation functions

  defp validate_location(edit, structure) do
    case edit.location.type do
      :start -> :ok  # Always valid
      :end -> :ok    # Always valid

      :before ->
        if marker_exists?(edit.location.relative_marker, structure) do
          :ok
        else
          {:error, {:marker_not_found, edit.location.relative_marker}}
        end

      :after ->
        if marker_exists?(edit.location.relative_marker, structure) do
          :ok
        else
          {:error, {:marker_not_found, edit.location.relative_marker}}
        end

      :within ->
        cond do
          edit.location.section_name ->
            if section_exists?(edit.location.section_name, structure) do
              :ok
            else
              {:error, {:section_not_found, edit.location.section_name}}
            end

          edit.location.pattern ->
            if pattern_matches?(edit.location.pattern, structure) do
              :ok
            else
              {:error, {:pattern_not_found, edit.location.pattern}}
            end

          true ->
            {:error, :insufficient_location_info}
        end

      :replace_all ->
        if edit.target_text && String.contains?(structure.raw_text, edit.target_text) do
          :ok
        else
          {:error, {:target_text_not_found, edit.target_text}}
        end
    end
  end

  defp validate_content(edit) do
    case edit.operation do
      :insert ->
        if edit.content && String.length(edit.content) > 0 do
          :ok
        else
          {:error, :missing_insert_content}
        end

      :replace ->
        if edit.content && edit.target_text do
          :ok
        else
          {:error, :missing_replacement_info}
        end

      :delete ->
        if edit.target_text do
          :ok
        else
          {:error, :missing_deletion_target}
        end

      :move ->
        # Move operations are complex, require source and destination
        if edit.location && edit.metadata[:destination] do
          :ok
        else
          {:error, :incomplete_move_specification}
        end
    end
  end

  defp validate_safety(edit, structure) do
    # Check for potentially dangerous edits
    cond do
      # Don't allow edits that would remove entire prompt
      deletes_too_much?(edit, structure) ->
        {:error, :excessive_deletion}

      # Don't allow malformed additions
      introduces_syntax_errors?(edit) ->
        {:error, :syntax_error_risk}

      # Don't allow recursive or self-referential edits
      creates_circular_reference?(edit) ->
        {:error, :circular_reference}

      # Don't allow edits that would make prompt too long
      exceeds_length_limit?(edit, structure) ->
        {:error, :length_limit_exceeded}

      true ->
        :ok
    end
  end

  defp validate_intent(edit, structure) do
    # Heuristic checks that edit preserves prompt purpose
    # This is best-effort and somewhat subjective

    # Don't allow removal of critical elements
    if edit.operation == :delete && removes_critical_content?(edit, structure) do
      {:error, :removes_critical_content}
    else
      :ok
    end
  end

  defp identify_conflicts(edits, structure) do
    # Find edits that conflict with each other

    # Group edits by location
    location_groups =
      edits
      |> Enum.group_by(&location_key(&1))
      |> Enum.filter(fn {_key, group} -> length(group) > 1 end)
      |> Enum.map(fn {_key, group} ->
        %ConflictGroup{
          edits: group,
          conflict_type: :overlapping,
          resolution_strategy: :highest_impact
        }
      end)

    # Find contradictory edits (add vs. remove same content)
    contradictory_groups = find_contradictory_edits(edits)

    # Find dependent edits (order matters)
    dependent_groups = find_dependent_edits(edits)

    location_groups ++ contradictory_groups ++ dependent_groups
  end

  # Helper functions

  defp marker_exists?(nil, _structure), do: false
  defp marker_exists?(marker, structure) do
    String.contains?(structure.raw_text, marker)
  end

  defp section_exists?(nil, _structure), do: false
  defp section_exists?(section_name, structure) do
    Enum.any?(structure.sections, &(&1.name == section_name))
  end

  defp pattern_matches?(nil, _structure), do: false
  defp pattern_matches?(pattern, structure) when is_binary(pattern) do
    String.contains?(structure.raw_text, pattern)
  end
  defp pattern_matches?(%Regex{} = pattern, structure) do
    Regex.match?(pattern, structure.raw_text)
  end

  defp deletes_too_much?(edit, structure) do
    if edit.operation == :delete && edit.target_text do
      deletion_ratio = String.length(edit.target_text) / structure.length
      deletion_ratio > 0.5  # Don't delete more than 50%
    else
      false
    end
  end

  defp introduces_syntax_errors?(edit) do
    # Basic checks for malformed content
    if edit.content do
      # Check for unclosed quotes, brackets, etc.
      quotes = Regex.scan(~r/"/, edit.content) |> length()
      single_quotes = Regex.scan(~r/'/, edit.content) |> length()
      open_brackets = Regex.scan(~r/\[/, edit.content) |> length()
      close_brackets = Regex.scan(~r/\]/, edit.content) |> length()

      rem(quotes, 2) != 0 or rem(single_quotes, 2) != 0 or
        open_brackets != close_brackets
    else
      false
    end
  end

  defp creates_circular_reference?(edit) do
    # Check if edit refers to itself
    if edit.content && edit.target_text do
      String.contains?(edit.content, edit.target_text)
    else
      false
    end
  end

  defp exceeds_length_limit?(edit, structure) do
    max_prompt_length = 10_000  # Configurable

    if edit.operation == :insert && edit.content do
      new_length = structure.length + String.length(edit.content)
      new_length > max_prompt_length
    else
      false
    end
  end

  defp removes_critical_content?(edit, structure) do
    # Heuristic: don't remove question marks, task descriptions, etc.
    if edit.target_text do
      critical_patterns = [
        "?",  # Questions
        "task:",
        "goal:",
        "objective:",
        "you must",
        "required"
      ]

      Enum.any?(critical_patterns, &String.contains?(String.downcase(edit.target_text), &1))
    else
      false
    end
  end

  defp location_key(edit) do
    # Generate a key representing the location
    {edit.location.type, edit.location.absolute_position, edit.location.section_name}
  end

  defp find_contradictory_edits(edits) do
    # Find pairs where one adds and another removes similar content
    additions = Enum.filter(edits, &(&1.operation == :insert))
    deletions = Enum.filter(edits, &(&1.operation == :delete))

    for add <- additions,
        del <- deletions,
        content_similar?(add.content, del.target_text) do
      %ConflictGroup{
        edits: [add, del],
        conflict_type: :contradictory,
        resolution_strategy: :highest_impact
      }
    end
  end

  defp find_dependent_edits(edits) do
    # Find edits where order matters
    # For now, return empty list (complex implementation)
    []
  end

  defp content_similar?(nil, _), do: false
  defp content_similar?(_, nil), do: false
  defp content_similar?(content1, content2) do
    # Simple similarity check
    intersection =
      MapSet.intersection(
        String.split(content1) |> MapSet.new(),
        String.split(content2) |> MapSet.new()
      )

    MapSet.size(intersection) > 3
  end
end
```

#### Implementation Checklist

- [ ] Create `EditValidator` module
- [ ] Implement `validate_edit/2` for single edit validation
- [ ] Implement `validate_edit_list/2` for batch validation
- [ ] Add validation functions:
  - [ ] `validate_location/2` - Check location exists
  - [ ] `validate_content/1` - Check content is well-formed
  - [ ] `validate_safety/2` - Check edit won't break prompt
  - [ ] `validate_intent/2` - Check purpose preservation
- [ ] Implement conflict detection:
  - [ ] Overlapping locations
  - [ ] Contradictory operations
  - [ ] Dependent edits
- [ ] Add safety checks:
  - [ ] Excessive deletion detection
  - [ ] Syntax error prevention
  - [ ] Circular reference detection
  - [ ] Length limit enforcement
- [ ] Unit tests for validation (30+ tests)

---

## Integration Points

### Input: ParsedReflection from Task 1.3.2

```elixir
# Reflector provides structured suggestions
{:ok, reflection} = Reflector.reflect_on_failure(trajectory_analysis,
  original_prompt: prompt
)

# Feed to SuggestionGenerator
{:ok, edit_plan} = SuggestionGenerator.generate_edit_plan(
  reflection,
  original_prompt: prompt
)
```

### Output: EditPlan for Task 1.4 Mutation Operators

```elixir
# SuggestionGenerator produces actionable edit plan
edit_plan.edits
|> Enum.filter(&(&1.validated and &1.impact_score > 0.7))
|> Enum.each(fn edit ->
  case edit.operation do
    :insert -> MutationOperator.apply_insertion(prompt, edit)
    :replace -> MutationOperator.apply_replacement(prompt, edit)
    :delete -> MutationOperator.apply_deletion(prompt, edit)
    :move -> MutationOperator.apply_move(prompt, edit)
  end
end)
```

### Supporting Modules

#### PromptStructureAnalyzer

```elixir
defmodule Jido.Runner.GEPA.SuggestionGeneration.PromptStructureAnalyzer do
  @moduledoc """
  Analyzes prompt structure to inform edit generation and validation.

  Identifies:
  - Sections (introduction, instructions, examples, constraints, closing)
  - Patterns (CoT triggers, formatting directives, placeholders)
  - Complexity (simple, moderate, complex)
  - Existing elements (examples present, constraints defined, etc.)
  """

  alias Jido.Runner.GEPA.SuggestionGeneration.PromptStructure

  def analyze(prompt_text) when is_binary(prompt_text) do
    %PromptStructure{
      raw_text: prompt_text,
      sections: identify_sections(prompt_text),
      has_examples: has_examples?(prompt_text),
      has_constraints: has_constraints?(prompt_text),
      has_cot_trigger: has_cot_trigger?(prompt_text),
      length: String.length(prompt_text),
      complexity: assess_complexity(prompt_text),
      patterns: identify_patterns(prompt_text)
    }
  end

  defp identify_sections(text) do
    # Heuristic section detection
    # Look for headers, blank lines, enumeration patterns
    sections = []

    # Check for explicit sections
    sections = sections ++ find_header_sections(text)

    # Infer implicit sections
    sections = sections ++ infer_logical_sections(text)

    sections
  end

  defp has_examples?(text) do
    patterns = [
      ~r/example:/i,
      ~r/for instance/i,
      ~r/such as/i,
      ~r/e\.g\./i
    ]

    Enum.any?(patterns, &Regex.match?(&1, text))
  end

  defp has_constraints?(text) do
    patterns = [
      ~r/constraint:/i,
      ~r/must not/i,
      ~r/requirement:/i,
      ~r/limit/i
    ]

    Enum.any?(patterns, &Regex.match?(&1, text))
  end

  defp has_cot_trigger?(text) do
    triggers = [
      "step by step",
      "think through",
      "reason about",
      "let's think",
      "work through"
    ]

    text_lower = String.downcase(text)
    Enum.any?(triggers, &String.contains?(text_lower, &1))
  end

  defp assess_complexity(text) do
    # Simple heuristics
    length = String.length(text)
    paragraphs = String.split(text, "\n\n") |> length()
    sentences = Regex.scan(~r/[.!?]+/, text) |> length()

    cond do
      length < 200 and paragraphs <= 2 -> :simple
      length > 1000 or paragraphs > 5 -> :complex
      true -> :moderate
    end
  end

  defp identify_patterns(text) do
    %{
      has_numbered_list: Regex.match?(~r/\d+\./, text),
      has_bulleted_list: Regex.match?(~r/[*-]\s/, text),
      has_code_blocks: Regex.match?(~r/```/, text),
      has_placeholders: Regex.match?(~r/\{.*?\}/, text)
    }
  end

  defp find_header_sections(text) do
    # Look for markdown headers or clear section markers
    []  # Simplified for now
  end

  defp infer_logical_sections(text) do
    # Infer sections from content patterns
    []  # Simplified for now
  end
end
```

#### ConflictResolver

```elixir
defmodule Jido.Runner.GEPA.SuggestionGeneration.ConflictResolver do
  @moduledoc """
  Resolves conflicts between incompatible edits.

  When multiple edits target the same location or contradict each other,
  this module selects which edits to keep based on configurable strategies.
  """

  alias Jido.Runner.GEPA.SuggestionGeneration.{ConflictGroup, PromptEdit}

  @doc """
  Resolves conflicts in a list of conflict groups.

  ## Parameters

  - `conflicts` - List of ConflictGroup
  - `strategy` - Resolution strategy (:highest_impact, :highest_priority, :first_wins)

  ## Returns

  - `{:ok, {selected_edits, rejected_edits}}` - Resolution results
  """
  def resolve_conflicts(conflicts, strategy \\ :highest_impact) do
    results =
      conflicts
      |> Enum.map(&resolve_conflict_group(&1, strategy))

    selected = Enum.flat_map(results, fn {selected, _} -> selected end)
    rejected = Enum.flat_map(results, fn {_, rejected} -> rejected end)

    {:ok, {selected, rejected}}
  end

  defp resolve_conflict_group(group, strategy) do
    case group.conflict_type do
      :overlapping ->
        resolve_overlapping(group.edits, strategy)

      :contradictory ->
        resolve_contradictory(group.edits, strategy)

      :dependent ->
        resolve_dependent(group.edits, strategy)
    end
  end

  defp resolve_overlapping(edits, :highest_impact) do
    winner = Enum.max_by(edits, & &1.impact_score)
    losers = edits -- [winner]
    {[winner], losers}
  end

  defp resolve_overlapping(edits, :highest_priority) do
    priority_order = %{high: 3, medium: 2, low: 1}
    winner = Enum.max_by(edits, &priority_order[&1.priority])
    losers = edits -- [winner]
    {[winner], losers}
  end

  defp resolve_overlapping(edits, :first_wins) do
    winner = List.first(edits)
    losers = tl(edits)
    {[winner], losers}
  end

  defp resolve_contradictory(edits, strategy) do
    # Addition typically preferred over deletion when contradictory
    additions = Enum.filter(edits, &(&1.operation == :insert))
    deletions = Enum.filter(edits, &(&1.operation == :delete))

    if length(additions) > 0 do
      {additions, deletions}
    else
      resolve_overlapping(edits, strategy)
    end
  end

  defp resolve_dependent(edits, _strategy) do
    # Order dependent edits by dependency graph
    # For now, preserve all and let mutation operator handle ordering
    {edits, []}
  end
end
```

#### LocationAnalyzer

```elixir
defmodule Jido.Runner.GEPA.SuggestionGeneration.LocationAnalyzer do
  @moduledoc """
  Analyzes prompt structure to identify optimal locations for edits.

  Uses both explicit markers (target_section) and heuristics (category-based)
  to determine where in a prompt an edit should be applied.
  """

  alias Jido.Runner.GEPA.SuggestionGeneration.{PromptLocation, PromptStructure}
  alias Jido.Runner.GEPA.Reflector.Suggestion

  @doc """
  Identifies the best location for a suggestion.

  ## Parameters

  - `suggestion` - Suggestion needing location
  - `structure` - Analyzed prompt structure
  - `opts` - Options:
    - `:prefer_existing_sections` - Try to place in existing sections (default: true)
    - `:create_sections` - Allow creation of new sections (default: true)

  ## Returns

  - `{:ok, PromptLocation.t()}` - Identified location
  - `{:error, reason}` - If location cannot be determined
  """
  def identify_location(%Suggestion{} = suggestion, %PromptStructure{} = structure, opts \\ []) do
    # Try explicit target first
    if suggestion.target_section do
      locate_by_section(suggestion.target_section, structure)
    else
      # Use heuristics based on category and type
      locate_by_heuristics(suggestion, structure, opts)
    end
  end

  defp locate_by_section(section_name, structure) do
    case find_section(section_name, structure) do
      {:ok, section} ->
        {:ok, %PromptLocation{
          type: :within,
          section_name: section_name,
          scope: :section
        }}

      :not_found ->
        {:error, {:section_not_found, section_name}}
    end
  end

  defp locate_by_heuristics(suggestion, structure, opts) do
    # Apply heuristics based on suggestion type and category
    location = case {suggestion.type, suggestion.category} do
      {:add, :constraint} ->
        find_constraints_section(structure) ||
          create_constraints_location(structure, opts)

      {:add, :example} ->
        find_examples_section(structure) ||
          create_examples_location(structure, opts)

      {:add, :reasoning} ->
        create_reasoning_trigger_location(structure)

      {:modify, :clarity} ->
        find_unclear_content(suggestion, structure)

      {:remove, _} ->
        find_removal_target(suggestion, structure)

      {:restructure, _} ->
        global_restructure_location()

      _ ->
        default_location(structure)
    end

    {:ok, location}
  end

  defp find_section(name, structure) do
    case Enum.find(structure.sections, &(&1.name == name)) do
      nil -> :not_found
      section -> {:ok, section}
    end
  end

  defp find_constraints_section(structure) do
    if structure.has_constraints do
      # Find existing constraints section
      section = Enum.find(structure.sections, &(&1.type == :constraints))
      if section do
        %PromptLocation{
          type: :within,
          section_name: section.name,
          scope: :section
        }
      end
    end
  end

  defp create_constraints_location(structure, opts) do
    if opts[:create_sections] != false do
      # Add after introduction, before examples
      %PromptLocation{
        type: :after,
        relative_marker: find_intro_end(structure),
        scope: :section
      }
    else
      %PromptLocation{type: :end, scope: :prompt}
    end
  end

  defp find_examples_section(structure) do
    if structure.has_examples do
      section = Enum.find(structure.sections, &(&1.type == :examples))
      if section do
        %PromptLocation{
          type: :within,
          section_name: section.name,
          scope: :section
        }
      end
    end
  end

  defp create_examples_location(structure, opts) do
    if opts[:create_sections] != false do
      # Add before closing section
      %PromptLocation{
        type: :before,
        relative_marker: find_closing_section(structure),
        scope: :section
      }
    else
      %PromptLocation{type: :end, scope: :prompt}
    end
  end

  defp create_reasoning_trigger_location(structure) do
    # CoT triggers typically go at the end
    %PromptLocation{
      type: :end,
      scope: :prompt
    }
  end

  defp find_unclear_content(suggestion, structure) do
    # Try to find content matching the suggestion's description
    # This is heuristic pattern matching
    if suggestion.specific_text do
      %PromptLocation{
        type: :replace_all,
        pattern: suggestion.specific_text,
        scope: :phrase
      }
    else
      default_location(structure)
    end
  end

  defp find_removal_target(suggestion, structure) do
    if suggestion.specific_text do
      %PromptLocation{
        type: :within,
        pattern: suggestion.specific_text,
        scope: :phrase
      }
    else
      {:error, :cannot_identify_removal_target}
    end
  end

  defp global_restructure_location do
    %PromptLocation{
      type: :start,
      scope: :prompt
    }
  end

  defp default_location(structure) do
    # When in doubt, append to end
    %PromptLocation{
      type: :end,
      scope: :prompt
    }
  end

  defp find_intro_end(structure) do
    # Find end of introduction section
    sections = structure.sections
    if length(sections) > 0 do
      List.first(sections).name
    else
      ""
    end
  end

  defp find_closing_section(structure) do
    # Find start of closing/summary section
    sections = structure.sections
    if length(sections) > 0 do
      List.last(sections).name
    else
      ""
    end
  end
end
```

---

## Main Orchestration Module

```elixir
defmodule Jido.Runner.GEPA.SuggestionGenerator do
  @moduledoc """
  Main orchestration for generating concrete prompt edits from LLM suggestions.

  This module implements Task 1.3.3, bridging between abstract reflection
  suggestions (Task 1.3.2) and concrete mutation operations (Task 1.4).

  ## Workflow

  1. Analyze prompt structure
  2. Convert suggestions to concrete edits
  3. Validate edit applicability
  4. Resolve conflicts between edits
  5. Rank edits by expected impact
  6. Return validated EditPlan

  ## Usage

      # Generate edit plan from reflection
      {:ok, reflection} = Reflector.reflect_on_failure(analysis, original_prompt: prompt)
      {:ok, edit_plan} = SuggestionGenerator.generate_edit_plan(reflection, original_prompt: prompt)

      # Apply high-impact edits
      edit_plan.edits
      |> Enum.filter(&(&1.impact_score > 0.7))
      |> Enum.each(&apply_edit/1)
  """

  require Logger

  alias Jido.Runner.GEPA.Reflector.{ParsedReflection, Suggestion}
  alias Jido.Runner.GEPA.SuggestionGeneration.{
    EditPlan,
    PromptEdit,
    PromptStructure,
    PromptStructureAnalyzer,
    EditBuilder,
    EditValidator,
    ConflictResolver,
    ImpactRanker,
    LocationAnalyzer
  }

  @doc """
  Generates a complete edit plan from reflection suggestions.

  ## Parameters

  - `reflection` - ParsedReflection from Reflector
  - `opts` - Options:
    - `:original_prompt` - The prompt being modified (required)
    - `:max_edits` - Maximum edits to generate (default: 10)
    - `:min_impact_score` - Minimum impact score to include (default: 0.3)
    - `:resolution_strategy` - Conflict resolution strategy (default: :highest_impact)
    - `:trajectory_analysis` - Optional trajectory analysis for impact ranking

  ## Returns

  - `{:ok, EditPlan.t()}` - Validated, ranked edit plan
  - `{:error, reason}` - If generation fails
  """
  def generate_edit_plan(%ParsedReflection{} = reflection, opts \\ []) do
    Logger.debug("Generating edit plan from reflection",
      suggestions: length(reflection.suggestions)
    )

    with {:ok, prompt} <- extract_prompt(opts),
         {:ok, structure} <- analyze_prompt(prompt),
         {:ok, edits} <- build_edits_from_suggestions(reflection.suggestions, structure, opts),
         {:ok, {valid_edits, conflicts}} <- validate_edits(edits, structure),
         {:ok, {selected_edits, _rejected}} <- resolve_conflicts(conflicts, opts),
         {:ok, ranked_edits} <- rank_edits(selected_edits ++ valid_edits, structure, opts) do

      plan = %EditPlan{
        id: generate_plan_id(),
        original_prompt: prompt,
        prompt_structure: structure,
        edits: ranked_edits,
        total_edits: length(ranked_edits),
        high_impact_edits: count_high_impact(ranked_edits),
        conflicts_resolved: length(conflicts),
        validated: true,
        ranked: true,
        metadata: %{
          reflection_confidence: reflection.confidence,
          suggestion_count: length(reflection.suggestions)
        }
      }

      Logger.debug("Edit plan generated successfully",
        total_edits: plan.total_edits,
        high_impact: plan.high_impact_edits
      )

      {:ok, plan}
    else
      {:error, reason} = error ->
        Logger.warning("Edit plan generation failed", reason: reason)
        error
    end
  end

  @doc """
  Applies filters to an edit plan to select specific edits.

  ## Parameters

  - `edit_plan` - EditPlan to filter
  - `filters` - Keyword list of filters:
    - `:min_impact` - Minimum impact score
    - `:priorities` - List of allowed priorities
    - `:categories` - List of allowed categories
    - `:operations` - List of allowed operations
    - `:limit` - Maximum number of edits

  ## Returns

  - `{:ok, EditPlan.t()}` - Filtered plan
  """
  def filter_edit_plan(%EditPlan{} = plan, filters \\ []) do
    filtered_edits =
      plan.edits
      |> apply_filters(filters)

    filtered_plan = %{plan |
      edits: filtered_edits,
      total_edits: length(filtered_edits),
      high_impact_edits: count_high_impact(filtered_edits)
    }

    {:ok, filtered_plan}
  end

  # Private functions

  defp extract_prompt(opts) do
    case opts[:original_prompt] do
      nil -> {:error, :missing_original_prompt}
      prompt -> {:ok, prompt}
    end
  end

  defp analyze_prompt(prompt) do
    structure = PromptStructureAnalyzer.analyze(prompt)
    {:ok, structure}
  end

  defp build_edits_from_suggestions(suggestions, structure, opts) do
    max_edits = opts[:max_edits] || 10

    edits =
      suggestions
      |> Enum.flat_map(fn suggestion ->
        case EditBuilder.build_edits(suggestion, structure, opts) do
          {:ok, edits} -> edits
          {:error, _} -> []
        end
      end)
      |> Enum.take(max_edits)

    {:ok, edits}
  end

  defp validate_edits(edits, structure) do
    EditValidator.validate_edit_list(edits, structure)
  end

  defp resolve_conflicts(conflicts, opts) do
    strategy = opts[:resolution_strategy] || :highest_impact
    ConflictResolver.resolve_conflicts(conflicts, strategy)
  end

  defp rank_edits(edits, structure, opts) do
    trajectory_analysis = opts[:trajectory_analysis]
    ImpactRanker.rank_edits(edits, structure, trajectory_analysis, opts)
  end

  defp count_high_impact(edits) do
    Enum.count(edits, &(&1.impact_score > 0.7))
  end

  defp apply_filters(edits, filters) do
    edits
    |> maybe_filter_by_impact(filters[:min_impact])
    |> maybe_filter_by_priorities(filters[:priorities])
    |> maybe_filter_by_categories(filters[:categories])
    |> maybe_filter_by_operations(filters[:operations])
    |> maybe_limit(filters[:limit])
  end

  defp maybe_filter_by_impact(edits, nil), do: edits
  defp maybe_filter_by_impact(edits, min_impact) do
    Enum.filter(edits, &(&1.impact_score >= min_impact))
  end

  defp maybe_filter_by_priorities(edits, nil), do: edits
  defp maybe_filter_by_priorities(edits, priorities) do
    Enum.filter(edits, &(&1.priority in priorities))
  end

  defp maybe_filter_by_categories(edits, nil), do: edits
  defp maybe_filter_by_categories(edits, categories) do
    Enum.filter(edits, &(&1.source_suggestion.category in categories))
  end

  defp maybe_filter_by_operations(edits, nil), do: edits
  defp maybe_filter_by_operations(edits, operations) do
    Enum.filter(edits, &(&1.operation in operations))
  end

  defp maybe_limit(edits, nil), do: edits
  defp maybe_limit(edits, limit) when is_integer(limit) do
    Enum.take(edits, limit)
  end

  defp generate_plan_id do
    "plan_#{:erlang.unique_integer([:positive])}"
  end
end
```

---

## Testing Strategy

### Unit Tests

#### EditBuilder Tests (25+ tests)
- Test addition edit generation
- Test modification edit generation
- Test deletion edit generation
- Test restructure edit generation
- Test location identification
- Test content generation from specific_text
- Test content generation from description
- Test category-specific formatting
- Test edge cases (missing data, invalid suggestions)

#### LocationAnalyzer Tests (20+ tests)
- Test section-based location
- Test heuristic location for each category
- Test location for each operation type
- Test default fallback location
- Test section creation vs. existing sections
- Test pattern matching for targets

#### EditValidator Tests (30+ tests)
- Test location validation (exists, doesn't exist)
- Test content validation (complete, incomplete)
- Test safety validation (excessive deletion, syntax errors)
- Test intent preservation
- Test conflict detection (overlapping, contradictory, dependent)
- Test batch validation
- Test edge cases

#### ConflictResolver Tests (15+ tests)
- Test overlapping location resolution
- Test contradictory operation resolution
- Test dependent edit ordering
- Test each resolution strategy
- Test empty conflicts
- Test large conflict groups

#### ImpactRanker Tests (20+ tests)
- Test base priority scoring
- Test category impact scoring
- Test specificity scoring
- Test structural fit scoring
- Test failure alignment scoring
- Test novelty scoring
- Test weighted scoring
- Test sorting by impact
- Test edge cases

#### PromptStructureAnalyzer Tests (15+ tests)
- Test section identification
- Test pattern detection (examples, constraints, CoT triggers)
- Test complexity assessment
- Test empty/minimal prompts
- Test complex multi-section prompts

### Integration Tests

#### End-to-End Generation (10+ tests)
```elixir
defmodule Jido.Runner.GEPA.SuggestionGeneratorIntegrationTest do
  use ExUnit.Case

  alias Jido.Runner.GEPA.{TrajectoryAnalyzer, Reflector, SuggestionGenerator}

  describe "end-to-end edit generation" do
    test "generates valid edit plan from failed trajectory" do
      # 1. Create failed trajectory
      trajectory = build_failed_math_trajectory()

      # 2. Analyze trajectory
      analysis = TrajectoryAnalyzer.analyze(trajectory)

      # 3. Get reflection from LLM (mocked)
      {:ok, reflection} = Reflector.reflect_on_failure(analysis,
        original_prompt: "Solve the math problem."
      )

      # 4. Generate edit plan
      {:ok, plan} = SuggestionGenerator.generate_edit_plan(reflection,
        original_prompt: "Solve the math problem.",
        trajectory_analysis: analysis
      )

      # Verify plan structure
      assert %EditPlan{} = plan
      assert plan.validated
      assert plan.ranked
      assert plan.total_edits > 0

      # Verify edits are concrete and actionable
      for edit <- plan.edits do
        assert edit.validated
        assert edit.operation in [:insert, :replace, :delete, :move]
        assert edit.location != nil

        # Verify edit has content for insert/replace operations
        if edit.operation in [:insert, :replace] do
          assert is_binary(edit.content)
          assert String.length(edit.content) > 0
        end
      end
    end

    test "generates high-impact reasoning improvements" do
      prompt = "Answer the question."
      trajectory = build_trajectory_without_reasoning()
      analysis = TrajectoryAnalyzer.analyze(trajectory)

      {:ok, reflection} = Reflector.reflect_on_failure(analysis,
        original_prompt: prompt
      )

      {:ok, plan} = SuggestionGenerator.generate_edit_plan(reflection,
        original_prompt: prompt
      )

      # Should suggest adding CoT trigger
      reasoning_edits =
        plan.edits
        |> Enum.filter(&(&1.source_suggestion.category == :reasoning))

      assert length(reasoning_edits) > 0
      assert Enum.any?(reasoning_edits, &(&1.impact_score > 0.7))
    end

    test "handles conflicts between suggestions" do
      # Create reflection with conflicting suggestions
      reflection = build_reflection_with_conflicts()

      {:ok, plan} = SuggestionGenerator.generate_edit_plan(reflection,
        original_prompt: "Test prompt."
      )

      # Conflicts should be resolved
      assert plan.conflicts_resolved > 0

      # No overlapping edits in final plan
      locations = Enum.map(plan.edits, &location_key/1)
      assert length(locations) == length(Enum.uniq(locations))
    end

    test "ranks edits by actual failure relevance" do
      trajectory = build_trajectory_with_specific_failure()
      analysis = TrajectoryAnalyzer.analyze(trajectory)

      {:ok, reflection} = Reflector.reflect_on_failure(analysis,
        original_prompt: "Solve this problem."
      )

      {:ok, plan} = SuggestionGenerator.generate_edit_plan(reflection,
        original_prompt: "Solve this problem.",
        trajectory_analysis: analysis
      )

      # Edits addressing the specific failure should rank higher
      top_edit = List.first(plan.edits)
      assert top_edit.impact_score > 0.7

      # Verify it addresses the failure
      failure = List.first(analysis.failure_points)
      assert edit_addresses_failure?(top_edit, failure)
    end
  end
end
```

---

## Implementation Phases

### Phase 1: Data Structures & Core Infrastructure (Days 1-2)
- [ ] Define TypedStruct modules (PromptEdit, EditPlan, PromptStructure, etc.)
- [ ] Create PromptStructureAnalyzer
- [ ] Implement basic prompt analysis (sections, patterns, complexity)
- [ ] Unit tests for data structures and analyzer
- [ ] **Deliverable**: Prompt structure analysis working

### Phase 2: Edit Generation (Days 3-4)
- [ ] Implement EditBuilder module
- [ ] Add type-specific edit builders (add, modify, remove, restructure)
- [ ] Implement LocationAnalyzer
- [ ] Add content generation logic
- [ ] Unit tests for edit building and location analysis
- [ ] **Deliverable**: Concrete edits generated from suggestions

### Phase 3: Validation & Conflict Resolution (Days 5-6)
- [ ] Implement EditValidator
- [ ] Add validation rules (location, content, safety, intent)
- [ ] Implement ConflictResolver
- [ ] Add conflict detection and resolution strategies
- [ ] Unit tests for validation and conflict resolution
- [ ] **Deliverable**: Valid, conflict-free edits

### Phase 4: Impact Ranking (Days 7-8)
- [ ] Implement ImpactRanker
- [ ] Add scoring factors (priority, category, specificity, etc.)
- [ ] Implement weighted scoring system
- [ ] Add CategoryStrategy mapping
- [ ] Unit tests for ranking
- [ ] **Deliverable**: Ranked edits by expected impact

### Phase 5: Main Orchestration & Integration (Days 9-10)
- [ ] Implement SuggestionGenerator main module
- [ ] Add generate_edit_plan/2 orchestration
- [ ] Implement filtering and plan manipulation
- [ ] Integration tests with Reflector
- [ ] End-to-end workflow tests
- [ ] **Deliverable**: Complete Task 1.3.3

---

## Success Criteria

### Functional Requirements
- [ ] Generate concrete edits from abstract LLM suggestions
- [ ] Identify locations for each edit in prompt structure
- [ ] Validate edits are applicable and safe
- [ ] Resolve conflicts between incompatible edits
- [ ] Rank edits by expected impact
- [ ] Produce validated EditPlan ready for mutation operators

### Quality Metrics
- [ ] Edit specificity: >80% of edits have concrete content
- [ ] Validation pass rate: >90% of generated edits are valid
- [ ] Conflict resolution: Successfully handle all conflict types
- [ ] Impact ranking accuracy: Top 3 edits address primary failures >70% of time
- [ ] Location accuracy: >85% of edits placed in appropriate locations

### Performance Metrics
- [ ] Generation latency: <1s for typical reflection (5-10 suggestions)
- [ ] Validation throughput: >100 edits/second
- [ ] Ranking speed: <500ms for 20 edits
- [ ] Memory efficiency: <10MB per edit plan

### Test Coverage
- [ ] Unit tests: 120+ tests across all modules
- [ ] Integration tests: 10+ end-to-end scenarios
- [ ] All tests passing
- [ ] Edge cases covered (empty prompts, conflicting edits, etc.)

---

## Integration with Task 1.4 (Mutation Operators)

Task 1.3.3 produces the EditPlan that Task 1.4 will consume:

```elixir
# Task 1.3.3 Output
{:ok, edit_plan} = SuggestionGenerator.generate_edit_plan(reflection,
  original_prompt: prompt
)

# Task 1.4 Input
edit_plan.edits
|> Enum.filter(&(&1.validated and &1.impact_score > 0.7))
|> Enum.each(fn edit ->
  # Mutation operators apply the concrete edits
  {:ok, mutated_prompt} = MutationOperators.apply_edit(prompt, edit)
end)
```

### Mutation Operator Requirements

From this task, mutation operators need:

1. **Concrete Text**: Exact strings to insert/replace/delete
2. **Precise Locations**: Absolute positions or patterns to match
3. **Operation Type**: insert/replace/delete/move
4. **Validation Status**: Pre-validated edits ready to apply
5. **Priority/Impact**: Order of application if resources limited

Task 1.3.3 provides all these requirements, enabling Task 1.4 to focus on the mechanics of applying edits without re-validating or re-analyzing suggestions.

---

## Performance Considerations

### Edit Generation Cost
- **Prompt analysis**: O(n) where n = prompt length (fast, <10ms)
- **Edit building**: O(m) where m = suggestions count (typically 5-10)
- **Validation**: O(m * n) worst case (checking each edit against prompt)
- **Ranking**: O(m log m) for sorting
- **Total**: ~100-500ms for typical reflection

### Optimization Strategies
1. **Cache prompt structure analysis** when processing multiple reflections
2. **Batch validate edits** instead of one-at-a-time
3. **Lazy conflict detection** - only check when locations overlap
4. **Parallel ranking** - score edits concurrently
5. **Short-circuit validation** - fail fast on first validation error

### Memory Usage
- **PromptStructure**: ~5-10KB per prompt
- **PromptEdit**: ~1-2KB per edit
- **EditPlan**: ~10-20KB with 10 edits
- **Total per reflection**: <100KB typically

---

## Error Handling

### Graceful Degradation

When components fail, provide partial results:

```elixir
# If location analysis fails for some suggestions
{:ok, partial_plan} = SuggestionGenerator.generate_edit_plan(reflection,
  original_prompt: prompt,
  allow_partial: true  # Continue even if some edits fail
)

# partial_plan contains only successfully generated edits
```

### Error Recovery Strategies

1. **Missing specific_text**: Generate content from description
2. **Location not found**: Fall back to default location (end of prompt)
3. **Validation failures**: Log and exclude invalid edits, continue with valid ones
4. **Conflict resolution fails**: Keep all edits, mark as unresolved, let downstream handle
5. **Ranking failures**: Use base priority as fallback ranking

---

## Future Enhancements (Post-1.3.3)

### LLM-Assisted Edit Refinement
- Use LLM to expand vague descriptions into concrete text
- Generate multiple edit variations, score with LLM
- Ask LLM to validate edits before application

### Learning from Applied Edits
- Track which edits actually improve prompts
- Adjust impact scoring based on historical effectiveness
- Build edit templates from successful patterns

### Incremental Edit Application
- Apply edits one-at-a-time with evaluation between
- Detect when edit degrades performance, rollback
- Build optimal edit sequences through experimentation

### Semantic Edit Understanding
- Use embeddings to detect semantic conflicts (not just textual)
- Cluster similar edits for batch application
- Detect when edits redundantly express same idea

---

## Documentation Checklist

- [ ] Module documentation (@moduledoc)
- [ ] Function documentation (@doc)
- [ ] Type specifications (@spec)
- [ ] Usage examples in docs
- [ ] Integration guide with Task 1.3.2 and Task 1.4
- [ ] Architecture diagrams (data flow, module relationships)
- [ ] API reference
- [ ] Testing guide

---

## Review Checklist

Before considering Task 1.3.3 complete:

- [ ] All subtasks implemented (1.3.3.1 - 1.3.3.4)
- [ ] TypedStruct data structures defined
- [ ] EditBuilder generating concrete edits
- [ ] LocationAnalyzer identifying edit locations
- [ ] EditValidator ensuring edit safety
- [ ] ConflictResolver handling conflicts
- [ ] ImpactRanker scoring edits
- [ ] PromptStructureAnalyzer working
- [ ] SuggestionGenerator orchestrating pipeline
- [ ] 120+ unit tests passing
- [ ] 10+ integration tests passing
- [ ] Mock infrastructure working
- [ ] Error handling comprehensive
- [ ] Performance acceptable (<500ms)
- [ ] Documentation complete
- [ ] Code review completed
- [ ] Integration with Task 1.3.2 verified
- [ ] Ready for Task 1.4 (Mutation Operators)

---

## References

### Existing Codebase
- `/home/ducky/code/agentjido/cot/lib/jido/runner/gepa/reflector.ex` - Task 1.3.2
- `/home/ducky/code/agentjido/cot/lib/jido/runner/gepa/reflection/suggestion_parser.ex` - Suggestion parsing
- `/home/ducky/code/agentjido/cot/lib/jido/runner/gepa/trajectory_analyzer.ex` - Trajectory analysis

### Phase 5 Documentation
- `/home/ducky/code/agentjido/cot/notes/planning/phase-05.md` - Overall plan
- Lines 174-182: Task 1.3.3 requirements

### Related Tasks
- Task 1.3.1: Trajectory Analysis (COMPLETE - provides failure context)
- Task 1.3.2: LLM-Guided Reflection (COMPLETE - provides suggestions)
- Task 1.3.4: Feedback Aggregation (NEXT)
- Task 1.4.x: Mutation Operators (FUTURE - consumes edit plans)

---

**Document Version**: 1.0  
**Created**: 2025-10-23  
**Author**: Planning Agent  
**Status**: Ready for Implementation Review
