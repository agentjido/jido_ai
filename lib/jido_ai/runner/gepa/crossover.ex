defmodule JidoAI.Runner.GEPA.Crossover do
  @moduledoc """
  Data structures and types for GEPA crossover operators.

  This module defines the core types used across the crossover system for combining
  successful elements from multiple high-performing prompts to create offspring prompts.

  ## Crossover vs Mutation

  - **Mutation** (Task 1.4.1): Modifies a single prompt
  - **Crossover** (Task 1.4.2): Combines multiple prompts

  ## Key Concepts

  - **PromptSegment**: A modular component identified within a prompt
  - **SegmentedPrompt**: A prompt analyzed and broken into segments
  - **CrossoverResult**: The result of combining parent prompts
  - **CompatibilityResult**: Assessment of whether prompts can be crossed

  ## Crossover Strategies

  - `:single_point` - Split at one point, swap halves
  - `:two_point` - Split at two points, swap middle section
  - `:uniform` - Randomly select each segment from either parent
  - `:semantic` - LLM-guided crossover respecting semantic coherence
  """

  use TypedStruct

  @type segment_type ::
          :instruction
          | :constraint
          | :example
          | :formatting
          | :reasoning_guide
          | :task_description
          | :output_format
          | :context

  @type crossover_strategy :: :single_point | :two_point | :uniform | :semantic

  @type compatibility_issue ::
          :incompatible_structure
          | :contradictory_constraints
          | :duplicate_content
          | :semantic_mismatch

  typedstruct module: PromptSegment do
    @moduledoc """
    A modular component of a prompt identified by segmentation.

    ## Examples

    - Instruction segment: "Solve this step by step"
    - Constraint segment: "Show all intermediate work"
    - Example segment: "Example: Input: 2+2, Output: 4"
    - Formatting segment: "Format your answer as JSON"

    ## Fields

    - `:id` - Unique identifier for this segment
    - `:type` - Category of segment (instruction, constraint, etc.)
    - `:content` - The actual text content
    - `:start_pos` - Character position where segment starts in original prompt
    - `:end_pos` - Character position where segment ends
    - `:parent_prompt_id` - ID of the prompt this segment came from
    - `:priority` - Importance level (affects crossover decisions)
    - `:metadata` - Additional information (confidence scores, patterns, etc.)
    """

    field(:id, String.t(), enforce: true)
    field(:type, JidoAI.Runner.GEPA.Crossover.segment_type(), enforce: true)
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

    This structure is produced by the Segmenter module and consumed by
    the Exchanger and Blender modules.

    ## Fields

    - `:prompt_id` - Unique identifier for this prompt
    - `:raw_text` - The original prompt text
    - `:segments` - List of identified segments
    - `:structure_type` - Classification of prompt complexity
    - `:metadata` - Additional analysis data
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

    The compatibility checker analyzes parent prompts to determine:
    - Can they be crossed without creating nonsense?
    - Are there contradictions that would make crossover problematic?
    - What strategy would work best?

    ## Fields

    - `:compatible` - Boolean indicating if crossover is recommended
    - `:issues` - List of detected problems
    - `:compatibility_score` - Numeric score from 0.0 (incompatible) to 1.0 (perfect match)
    - `:recommended_strategy` - Which crossover strategy to use
    - `:metadata` - Detailed analysis data
    """

    field(:compatible, boolean(), enforce: true)
    field(:issues, list(JidoAI.Runner.GEPA.Crossover.compatibility_issue()), default: [])
    field(:compatibility_score, float(), default: 0.0)
    field(:recommended_strategy, JidoAI.Runner.GEPA.Crossover.crossover_strategy() | nil)
    field(:metadata, map(), default: %{})
  end

  typedstruct module: CrossoverConfig do
    @moduledoc """
    Configuration for crossover operation.

    ## Fields

    - `:strategy` - Which crossover strategy to use
    - `:preserve_sections` - Segment types that should not be modified
    - `:min_segment_length` - Minimum character length for a valid segment
    - `:allow_blending` - Whether to merge overlapping segments
    - `:validate_offspring` - Whether to validate offspring before returning
    - `:max_offspring` - Maximum number of offspring to produce
    - `:metadata` - Additional configuration options
    """

    field(:strategy, JidoAI.Runner.GEPA.Crossover.crossover_strategy(), default: :semantic)

    field(:preserve_sections, list(JidoAI.Runner.GEPA.Crossover.segment_type()),
      default: [:task_description]
    )

    field(:min_segment_length, non_neg_integer(), default: 10)
    field(:allow_blending, boolean(), default: true)
    field(:validate_offspring, boolean(), default: true)
    field(:max_offspring, pos_integer(), default: 2)
    field(:metadata, map(), default: %{})
  end

  typedstruct module: CrossoverResult do
    @moduledoc """
    Result of a crossover operation.

    Contains the offspring prompts produced by combining parent prompts,
    along with metadata about which segments were exchanged or blended.

    ## Fields

    - `:id` - Unique identifier for this crossover operation
    - `:parent_ids` - IDs of the parent prompts
    - `:offspring_prompts` - The resulting combined prompts
    - `:strategy_used` - Which crossover strategy was applied
    - `:segments_exchanged` - Which segments were swapped
    - `:segments_blended` - Which segments were merged
    - `:validated` - Whether offspring passed validation
    - `:validation_score` - Quality score if validation was performed
    - `:metadata` - Additional operation details
    """

    field(:id, String.t(), enforce: true)
    field(:parent_ids, list(String.t()), enforce: true)
    field(:offspring_prompts, list(String.t()), default: [])
    field(:strategy_used, JidoAI.Runner.GEPA.Crossover.crossover_strategy(), enforce: true)
    field(:segments_exchanged, list(PromptSegment.t()), default: [])
    field(:segments_blended, list(PromptSegment.t()), default: [])
    field(:validated, boolean(), default: false)
    field(:validation_score, float() | nil)
    field(:metadata, map(), default: %{})
  end
end
