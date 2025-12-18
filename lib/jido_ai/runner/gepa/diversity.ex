defmodule Jido.AI.Runner.GEPA.Diversity do
  @moduledoc """
  Data structures and types for GEPA diversity enforcement.

  This module defines the core types used across the diversity enforcement system
  for preventing population convergence and maintaining genetic diversity.

  ## Key Concepts

  - **Similarity**: How alike two prompts are (0.0 = completely different, 1.0 = identical)
  - **Diversity**: How varied the population is overall
  - **Novelty**: How unique a prompt's behavior is compared to history

  ## Diversity Levels

  - `:critical` - Population nearly converged, immediate intervention needed
  - `:low` - Low diversity, diversity-promoting mutations recommended
  - `:moderate` - Acceptable diversity, monitor
  - `:healthy` - Good diversity, normal operations
  - `:excellent` - High diversity, may reduce exploration

  ## Similarity Strategies

  - `:text` - Text-based similarity (Levenshtein, Jaccard, n-grams)
  - `:structural` - Structure-based similarity (segment types, patterns)
  - `:semantic` - Embedding-based similarity (cosine distance)
  - `:behavioral` - Trajectory-based similarity (execution paths)
  - `:composite` - Weighted combination of multiple strategies
  """

  use TypedStruct

  @type similarity_strategy :: :text | :structural | :semantic | :behavioral | :composite
  @type diversity_level :: :critical | :low | :moderate | :healthy | :excellent

  typedstruct module: SimilarityResult do
    @moduledoc """
    Result of comparing two prompts for similarity.

    ## Fields

    - `:prompt_a_id` - ID of first prompt
    - `:prompt_b_id` - ID of second prompt
    - `:similarity_score` - Overall similarity (0.0 = different, 1.0 = identical)
    - `:strategy_used` - Which strategy was used for comparison
    - `:components` - Breakdown by similarity type (text, structural, etc.)
    - `:metadata` - Additional comparison details
    """

    field(:prompt_a_id, String.t(), enforce: true)
    field(:prompt_b_id, String.t(), enforce: true)
    field(:similarity_score, float(), enforce: true)
    # credo:disable-for-next-line Credo.Check.Design.AliasUsage
    field(:strategy_used, Jido.AI.Runner.GEPA.Diversity.similarity_strategy(), enforce: true)
    field(:components, map(), default: %{})
    field(:metadata, map(), default: %{})
  end

  typedstruct module: SimilarityMatrix do
    @moduledoc """
    Pairwise similarity scores for all prompts in population.

    Efficiently stores O(P²) similarity comparisons for P prompts.

    ## Fields

    - `:prompt_ids` - Ordered list of prompt IDs
    - `:scores` - Map of {id_a, id_b} => similarity_score
    - `:strategy_used` - Similarity strategy used
    - `:computed_at` - When matrix was computed
    - `:metadata` - Statistics and caching info
    """

    field(:prompt_ids, list(String.t()), default: [])
    field(:scores, map(), default: %{})
    # credo:disable-for-next-line Credo.Check.Design.AliasUsage
    field(:strategy_used, Jido.AI.Runner.GEPA.Diversity.similarity_strategy(), enforce: true)
    field(:computed_at, DateTime.t(), enforce: true)
    field(:metadata, map(), default: %{})
  end

  typedstruct module: DiversityMetrics do
    @moduledoc """
    Comprehensive diversity metrics for a population.

    ## Fields

    - `:pairwise_diversity` - Average pairwise distance (1 - similarity)
    - `:entropy` - Information-theoretic diversity measure
    - `:coverage` - Proportion of unique vs total prompts
    - `:uniqueness_ratio` - Fraction of prompts below similarity threshold
    - `:clustering_coefficient` - How clustered the population is
    - `:convergence_risk` - Estimated risk of premature convergence (0.0-1.0)
    - `:diversity_level` - Categorical assessment
    - `:metadata` - Additional statistics
    """

    field(:pairwise_diversity, float(), default: 0.0)
    field(:entropy, float(), default: 0.0)
    field(:coverage, float(), default: 0.0)
    field(:uniqueness_ratio, float(), default: 0.0)
    field(:clustering_coefficient, float(), default: 0.0)
    field(:convergence_risk, float(), default: 0.0)
    # credo:disable-for-next-line Credo.Check.Design.AliasUsage
    field(:diversity_level, Jido.AI.Runner.GEPA.Diversity.diversity_level(), default: :moderate)
    field(:metadata, map(), default: %{})
  end

  typedstruct module: DiversityConfig do
    @moduledoc """
    Configuration for diversity enforcement.

    ## Fields

    - `:similarity_strategy` - Which strategy to use for detection
    - `:similarity_threshold` - Above this = considered duplicate
    - `:min_diversity` - Minimum acceptable pairwise diversity
    - `:enable_novelty_rewards` - Whether to use novelty scoring
    - `:novelty_weight` - How much to weight novelty vs fitness
    - `:diversity_promotion_threshold` - Trigger intervention below this
    - `:metadata` - Additional configuration
    """

    # credo:disable-for-next-line Credo.Check.Design.AliasUsage
    field(:similarity_strategy, Jido.AI.Runner.GEPA.Diversity.similarity_strategy(),
      default: :text
    )

    field(:similarity_threshold, float(), default: 0.85)
    field(:min_diversity, float(), default: 0.3)
    field(:enable_novelty_rewards, boolean(), default: true)
    field(:novelty_weight, float(), default: 0.2)
    field(:diversity_promotion_threshold, float(), default: 0.25)
    field(:metadata, map(), default: %{})
  end

  typedstruct module: NoveltyScore do
    @moduledoc """
    Novelty score for a single prompt.

    ## Fields

    - `:prompt_id` - ID of the prompt
    - `:novelty_score` - How novel this prompt is (0.0-1.0)
    - `:k_nearest_distance` - Average distance to k nearest neighbors
    - `:behavioral_features` - Feature vector characterizing behavior
    - `:metadata` - Additional scoring details
    """

    field(:prompt_id, String.t(), enforce: true)
    field(:novelty_score, float(), enforce: true)
    field(:k_nearest_distance, float(), default: 0.0)
    field(:behavioral_features, list(float()), default: [])
    field(:metadata, map(), default: %{})
  end

  typedstruct module: DiversityReport do
    @moduledoc """
    Complete diversity analysis report for a population.

    ## Fields

    - `:generation` - Which generation this report is for
    - `:population_size` - Number of prompts analyzed
    - `:metrics` - DiversityMetrics struct
    - `:similarity_matrix` - Full similarity matrix
    - `:novelty_scores` - NoveltyScore for each prompt
    - `:action_recommended` - What action to take
    - `:computed_at` - When report was generated
    - `:metadata` - Additional analysis data
    """

    field(:generation, non_neg_integer(), enforce: true)
    field(:population_size, non_neg_integer(), enforce: true)
    field(:metrics, DiversityMetrics.t(), enforce: true)
    field(:similarity_matrix, SimilarityMatrix.t() | nil)
    field(:novelty_scores, list(NoveltyScore.t()), default: [])
    field(:action_recommended, atom(), default: :none)
    field(:computed_at, DateTime.t(), enforce: true)
    field(:metadata, map(), default: %{})
  end
end
