defmodule Jido.AI.Runner.GEPA.SuggestionGeneration do
  @moduledoc """
  Data structures for GEPA suggestion generation (Task 1.3.3).

  This module defines the core types used to convert abstract LLM suggestions
  (from Task 1.3.2 Reflector) into concrete prompt edits that can be applied
  by mutation operators (Task 1.4).

  ## Key Concepts

  - **PromptLocation**: Identifies WHERE in a prompt to apply an edit
  - **PromptEdit**: A concrete modification operation with text and location
  - **PromptStructure**: Analyzed prompt organization (sections, patterns)
  - **EditPlan**: Complete validated plan of all edits to apply
  - **ConflictGroup**: Group of incompatible edits requiring resolution

  ## Data Flow

      ParsedReflection (from Reflector)
          ↓
      SuggestionGenerator
          ↓
      EditPlan (to Mutation Operators)
  """

  use TypedStruct

  alias Jido.AI.Runner.GEPA.Reflector.Suggestion, as: ReflectorSuggestion

  # Type definitions

  @type edit_operation :: :insert | :replace | :delete | :move
  @type edit_scope :: :word | :phrase | :sentence | :paragraph | :section | :prompt
  @type location_type :: :start | :end | :before | :after | :within | :replace_all
  @type complexity :: :simple | :moderate | :complex
  @type conflict_type :: :overlapping | :contradictory | :dependent
  @type resolution_strategy :: :highest_impact | :highest_priority | :first | :merge

  typedstruct module: PromptLocation do
    @moduledoc """
    Identifies a specific location within a prompt for applying an edit.

    Supports multiple location specification methods:
    - Absolute: Character offset from start
    - Relative: Before/after a marker text
    - Section-based: Within a named section
    - Pattern-based: Matching a regex or text pattern

    ## Examples

        # Insert at end of prompt
        %PromptLocation{type: :end, scope: :prompt}

        # Insert before a specific marker
        %PromptLocation{
          type: :before,
          relative_marker: "Let's solve this step by step",
          scope: :sentence
        }

        # Replace within a section
        %PromptLocation{
          type: :within,
          section_name: "constraints",
          pattern: ~r/must (\\w+)/,
          scope: :phrase
        }
    """

    field(:type, Jido.AI.Runner.GEPA.SuggestionGeneration.location_type(), enforce: true)
    field(:absolute_position, non_neg_integer() | nil)
    field(:relative_marker, String.t() | nil)
    field(:section_name, String.t() | nil)
    field(:pattern, String.t() | Regex.t() | nil)
    field(:scope, Jido.AI.Runner.GEPA.SuggestionGeneration.edit_scope(), default: :phrase)
    field(:confidence, float(), default: 1.0)
  end

  typedstruct module: PromptEdit do
    @moduledoc """
    A concrete edit operation to apply to a prompt.

    Represents the actual text modification that mutation operators
    will perform, with all details specified: operation type, location,
    content, and metadata.

    ## Fields

    - `id`: Unique identifier for tracking
    - `operation`: Type of edit (:insert, :replace, :delete, :move)
    - `location`: Where to apply the edit
    - `content`: Text to insert or replace with (nil for deletions)
    - `target_text`: Text being replaced or deleted (nil for insertions)
    - `source_suggestion`: Original LLM suggestion this edit came from
    - `rationale`: Why this edit improves the prompt
    - `impact_score`: Expected effectiveness (0.0-1.0)
    - `priority`: Importance level from source suggestion
    - `validated`: Whether edit has passed validation checks
    - `conflicts_with`: IDs of edits that conflict with this one
    - `depends_on`: IDs of edits that must be applied before this one

    ## Examples

        # Insert new instruction at end
        %PromptEdit{
          id: "edit_001",
          operation: :insert,
          location: %PromptLocation{type: :end, scope: :prompt},
          content: "Show all intermediate steps.",
          source_suggestion: suggestion,
          rationale: "Adds explicit instruction for step visibility",
          impact_score: 0.75,
          priority: :high
        }

        # Replace vague text with specific instruction
        %PromptEdit{
          id: "edit_002",
          operation: :replace,
          location: %PromptLocation{
            type: :within,
            pattern: "solve this problem",
            scope: :phrase
          },
          content: "solve this problem step by step, showing your work",
          target_text: "solve this problem",
          source_suggestion: suggestion,
          rationale: "Makes instruction more explicit",
          impact_score: 0.65
        }
    """

    field(:id, String.t(), enforce: true)
    field(:operation, Jido.AI.Runner.GEPA.SuggestionGeneration.edit_operation(), enforce: true)
    field(:location, PromptLocation.t(), enforce: true)
    field(:content, String.t() | nil)
    field(:target_text, String.t() | nil)

    field(:source_suggestion, ReflectorSuggestion.t(), enforce: true)
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
    that inform where edits can be applied and how the prompt
    is organized.

    ## Fields

    - `raw_text`: Original prompt text
    - `sections`: Identified sections (e.g., [{name: "instructions", start: 0, end: 100}])
    - `has_examples`: Whether prompt includes examples
    - `has_constraints`: Whether prompt has explicit constraints
    - `has_cot_trigger`: Whether prompt has chain-of-thought trigger phrases
    - `length`: Character count of prompt
    - `complexity`: Assessed complexity level
    - `patterns`: Identified patterns (e.g., %{step_by_step: true, numbered_list: false})
    - `metadata`: Additional analysis data

    ## Examples

        %PromptStructure{
          raw_text: "Solve this math problem...",
          sections: [
            %{name: "task", start: 0, end: 50},
            %{name: "constraints", start: 51, end: 100}
          ],
          has_examples: false,
          has_constraints: true,
          has_cot_trigger: false,
          length: 100,
          complexity: :simple,
          patterns: %{imperative_voice: true}
        }
    """

    field(:raw_text, String.t(), enforce: true)
    field(:sections, list(map()), default: [])
    field(:has_examples, boolean(), default: false)
    field(:has_constraints, boolean(), default: false)
    field(:has_cot_trigger, boolean(), default: false)
    field(:length, non_neg_integer(), enforce: true)

    field(:complexity, Jido.AI.Runner.GEPA.SuggestionGeneration.complexity(), default: :moderate)
    field(:patterns, map(), default: %{})
    field(:metadata, map(), default: %{})
  end

  typedstruct module: EditPlan do
    @moduledoc """
    Complete plan of edits to apply to a prompt.

    Contains all validated, conflict-resolved, ranked edits ready
    for mutation operators to apply. Represents the final output
    of the suggestion generation process.

    ## Fields

    - `id`: Unique identifier for this plan
    - `original_prompt`: The prompt these edits apply to
    - `prompt_structure`: Analyzed structure of the prompt
    - `edits`: List of all edits in priority order
    - `total_edits`: Count of edits
    - `high_impact_edits`: Count of high-impact edits
    - `conflicts_resolved`: Number of conflicts that were resolved
    - `validated`: Whether all edits have been validated
    - `ranked`: Whether edits have been ranked by impact
    - `metadata`: Additional plan data

    ## Examples

        %EditPlan{
          id: "plan_001",
          original_prompt: "Solve this problem",
          prompt_structure: %PromptStructure{...},
          edits: [edit1, edit2, edit3],
          total_edits: 3,
          high_impact_edits: 1,
          conflicts_resolved: 1,
          validated: true,
          ranked: true
        }
    """

    field(:id, String.t(), enforce: true)
    field(:original_prompt, String.t(), enforce: true)

    field(
      :prompt_structure,
      PromptStructure.t(),
      enforce: true
    )

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

    Represents edits that overlap in location, contradict each other,
    or have dependencies that create conflicts. Requires resolution
    strategy to select which edits to keep.

    ## Conflict Types

    - `:overlapping` - Edits affect the same location
    - `:contradictory` - Edits have opposing effects
    - `:dependent` - Edits have circular or unresolvable dependencies

    ## Resolution Strategies

    - `:highest_impact` - Keep edit with highest impact score
    - `:highest_priority` - Keep edit with highest priority
    - `:first` - Keep first edit encountered
    - `:merge` - Attempt to merge edits if possible

    ## Examples

        %ConflictGroup{
          edits: [edit1, edit2],
          conflict_type: :overlapping,
          resolution_strategy: :highest_impact,
          resolved: true,
          selected_edit: edit1
        }
    """

    field(:edits, list(PromptEdit.t()), enforce: true)

    field(
      :conflict_type,
      Jido.AI.Runner.GEPA.SuggestionGeneration.conflict_type(),
      enforce: true
    )

    field(
      :resolution_strategy,
      Jido.AI.Runner.GEPA.SuggestionGeneration.resolution_strategy(),
      default: :highest_impact
    )

    field(:resolved, boolean(), default: false)
    field(:selected_edit, PromptEdit.t() | nil)
  end
end
