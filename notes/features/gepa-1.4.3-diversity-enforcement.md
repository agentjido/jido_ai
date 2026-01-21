# GEPA Task 1.4.3: Diversity Enforcement - Feature Planning

## Overview

This document provides comprehensive planning for implementing GEPA Task 1.4.3: Diversity Enforcement. This task implements mechanisms to prevent population convergence and maintain genetic diversity throughout the evolutionary optimization process. While mutations and crossover introduce variations, diversity enforcement actively monitors and promotes population heterogeneity to ensure the search doesn't prematurely converge to local optima.

## Status

- **Phase**: 5 (GEPA Optimization)
- **Stage**: 1 (Foundation)
- **Section**: 1.4 (Mutation & Variation Strategies)
- **Task**: 1.4.3 (Diversity Enforcement)
- **Status**: Planning
- **Branch**: TBD (suggest: `feature/gepa-1.4.3-diversity-enforcement`)

## Prerequisites Completed

### Task 1.4.1: Targeted Mutation Operators
- EditMutation, AdditionMutation, DeletionMutation, ReplacementMutation
- Mutation orchestrator and validation infrastructure
- History tracking for mutation operations

### Task 1.4.2: Crossover & Combination Operators
- Single-point, two-point, uniform, and semantic crossover strategies
- Prompt segmentation and compatibility checking
- Blending mechanisms for combining prompt components

### Related Infrastructure
- Population management (`lib/jido_ai/runner/gepa/population.ex`)
  - Basic diversity metric (unique prompts / population size)
  - Candidate tracking and fitness management
- TrajectoryAnalyzer for behavioral analysis
- FeedbackAggregation with similarity detection (Levenshtein, Jaccard)

## Context & Motivation

### The Diversity Problem in Genetic Algorithms

Evolutionary algorithms face a fundamental tension:

**Exploitation** (Selection Pressure):
- Favors high-performing prompts
- Drives convergence toward local optima
- Risk: Premature convergence, losing genetic diversity

**Exploration** (Diversity Maintenance):
- Maintains population variety
- Explores different solution regions
- Risk: Slow convergence, wasting evaluations

Without diversity enforcement, genetic algorithms often **converge too quickly** to suboptimal solutions because:
1. High-fitness prompts dominate selection
2. Similar offspring are produced repeatedly
3. Population becomes homogeneous
4. Search gets trapped in local optima

### Why Diversity Matters for GEPA

GEPA optimizes prompts in a complex, high-dimensional search space where:

1. **Multiple Valid Approaches Exist**: Different prompting strategies can achieve similar performance
2. **Synergistic Combinations**: Diverse prompts can be crossed to create superior offspring
3. **Robustness to Evaluation Noise**: LLM evaluations have variance; diversity provides multiple paths forward
4. **Task Generalization**: Diverse prompts may generalize better to related tasks
5. **Avoiding Linguistic Convergence**: Prevents population from converging to slight variations of the same phrasing

### Research-Backed Approaches

Recent research (2024-2025) shows several effective diversity enforcement techniques:

**Quality-Diversity Algorithms**:
- Dominated Novelty Search: Dynamic fitness transformations for local competition
- MAP-Elites: Maintains archive of best solutions across behavior space
- Novelty Search: Rewards behavioral uniqueness rather than fitness alone

**Diversity Metrics**:
- Genetic distance measures (edit distance for programs)
- Behavioral characterization (execution trajectory similarity)
- Phenotypic diversity (output-based distinctiveness)
- Crowding distance (NSGA-II approach)

**Enforcement Mechanisms**:
- Fitness sharing: Penalize similar solutions
- Niching: Maintain distinct sub-populations
- Novelty rewards: Bonus for unique behaviors
- Diversity-promoting mutation: Increase variation when diversity drops

### GEPA's Diversity Challenge

Unlike traditional genetic algorithms with fixed genotype encodings, prompts are:
- **Variable length** (10 to 10,000+ characters)
- **Hierarchically structured** (instructions, examples, constraints)
- **Semantically complex** (similar text may have different meaning, and vice versa)
- **Context-dependent** (effectiveness depends on task and LLM)

This requires diversity metrics that capture **both syntactic and semantic differences**.

## Problem Statement

### Core Challenge

How do we maintain a diverse population of prompts that:
1. Prevents premature convergence to local optima
2. Balances diversity with quality (avoid random noise)
3. Captures both syntactic and semantic differences
4. Scales efficiently to populations of 20-100 prompts
5. Integrates with existing mutation and crossover operators

### Technical Challenges

1. **Similarity Detection**: How to measure if two prompts are similar?
   - Text-based: Levenshtein distance, Jaccard similarity
   - Structure-based: Segment overlap, component similarity
   - Semantic: Embedding-based similarity (requires LLM calls)
   - Behavioral: Trajectory/outcome similarity (expensive)

2. **Diversity Metrics**: How to quantify population diversity?
   - Pairwise diversity (average distance between prompts)
   - Entropy-based measures
   - Coverage metrics (how much of search space is explored)

3. **Diversity-Promoting Mutation**: How to increase variation?
   - Random injection of novel prompts
   - Mutation rate adaptation
   - Targeted diversification of homogeneous regions

4. **Novelty Rewards**: How to incentivize exploration?
   - Behavioral novelty scoring
   - Archive-based comparison
   - Balance with fitness optimization

### Key Questions

- What similarity threshold indicates two prompts are "too similar"?
- Should we use cheap text-based metrics or expensive semantic metrics?
- How do we balance diversity with quality (avoid rewarding gibberish)?
- When should diversity enforcement trigger? (continuous monitoring, threshold-based?)
- How do we integrate novelty scores with fitness scores in selection?

## Solution Overview

### High-Level Approach

We'll implement a **multi-layered diversity enforcement system**:

1. **Similarity Detection** (1.4.3.1): Identify duplicate and near-duplicate prompts
2. **Diversity Metrics** (1.4.3.2): Quantify population-level variation
3. **Diversity-Promoting Mutation** (1.4.3.3): Increase variation when needed
4. **Novelty Rewards** (1.4.3.4): Encourage exploration of new approaches

### Architecture

```
lib/jido_ai/runner/gepa/diversity/
  ├── similarity_detector.ex          # Similarity detection (1.4.3.1)
  ├── metrics.ex                       # Diversity metrics (1.4.3.2)
  ├── promoter.ex                      # Diversity-promoting mutation (1.4.3.3)
  ├── novelty_scorer.ex                # Novelty rewards (1.4.3.4)
  ├── strategies/
  │   ├── text_similarity.ex           # Text-based similarity
  │   ├── structural_similarity.ex     # Structure-based similarity
  │   ├── semantic_similarity.ex       # Embedding-based similarity
  │   └── behavioral_similarity.ex     # Trajectory-based similarity
  └── types.ex                         # Data structures

test/jido_ai/runner/gepa/diversity/
  ├── similarity_detector_test.exs
  ├── metrics_test.exs
  ├── promoter_test.exs
  ├── novelty_scorer_test.exs
  └── strategies/
      ├── text_similarity_test.exs
      ├── structural_similarity_test.exs
      ├── semantic_similarity_test.exs
      └── behavioral_similarity_test.exs
```

### Integration Points

**With Population Module**:
- Extend `Population` struct with diversity tracking
- Add diversity thresholds to population configuration
- Integrate diversity metrics into population statistics

**With Mutation Operators**:
- Promoter can trigger when diversity drops below threshold
- Mutation rates adapt based on diversity metrics
- Targeted diversification of homogeneous prompts

**With Selection (Future Stage 2)**:
- Novelty scores combined with fitness for selection
- Crowding distance calculations for Pareto frontier
- Fitness sharing to penalize similar solutions

**With Crossover Operators**:
- Compatibility checker considers diversity
- Discourage crossing very similar parents
- Promote crossing diverse high-performers

### Data Flow

```
[Population of Prompts]
    ↓
SimilarityDetector (detect near-duplicates)
    ↓ [SimilarityMatrix.t()]
DiversityMetrics (calculate population diversity)
    ↓ [DiversityReport.t()]
Threshold Check (is diversity too low?)
    ↓
If low diversity:
  └→ DiversityPromoter (inject variation)
       ├→ Random injection
       ├→ Mutation rate increase
       └→ Targeted diversification
    ↓
NoveltyScorerr (reward novel approaches)
    ↓ [NoveltyScores.t()]
[Updated Population with Diversity Tracking]
```

## Technical Details

### Data Structures

```elixir
defmodule Jido.AI.Runner.GEPA.Diversity do
  use TypedStruct

  @type similarity_strategy :: :text | :structural | :semantic | :behavioral | :composite
  @type diversity_level :: :critical | :low | :moderate | :healthy | :excellent

  typedstruct module: SimilarityResult do
    @moduledoc """
    Result of comparing two prompts for similarity.
    """

    field(:prompt_a_id, String.t(), enforce: true)
    field(:prompt_b_id, String.t(), enforce: true)
    field(:similarity_score, float(), enforce: true)  # 0.0 (different) to 1.0 (identical)
    field(:strategy_used, similarity_strategy(), enforce: true)
    field(:components, map(), default: %{})  # Breakdown by similarity type
    field(:metadata, map(), default: %{})
  end

  typedstruct module: SimilarityMatrix do
    @moduledoc """
    Pairwise similarity scores for all prompts in population.
    """

    field(:population_id, String.t(), enforce: true)
    field(:generation, non_neg_integer(), enforce: true)
    field(:similarities, map(), default: %{})  # {id_a, id_b} -> SimilarityResult
    field(:avg_similarity, float(), default: 0.0)
    field(:min_similarity, float(), default: 0.0)
    field(:max_similarity, float(), default: 1.0)
    field(:near_duplicates, list({String.t(), String.t()}), default: [])
    field(:computed_at, integer(), enforce: true)
  end

  typedstruct module: DiversityMetrics do
    @moduledoc """
    Comprehensive diversity measurements for a population.
    """

    field(:population_id, String.t(), enforce: true)
    field(:generation, non_neg_integer(), enforce: true)
    field(:population_size, pos_integer(), enforce: true)

    # Core metrics
    field(:pairwise_diversity, float(), default: 0.0)     # Average distance between prompts
    field(:entropy, float(), default: 0.0)                # Shannon entropy of features
    field(:coverage, float(), default: 0.0)               # Portion of search space explored

    # Component-level diversity
    field(:text_diversity, float(), default: 0.0)         # Character-level variation
    field(:structural_diversity, float(), default: 0.0)   # Segment structure variation
    field(:behavioral_diversity, float(), default: 0.0)   # Execution pattern variation

    # Population characteristics
    field(:unique_ratio, float(), default: 1.0)           # Unique prompts / total
    field(:cluster_count, non_neg_integer(), default: 0)  # Number of distinct clusters
    field(:largest_cluster_size, non_neg_integer(), default: 0)

    # Health indicators
    field(:diversity_level, diversity_level(), default: :moderate)
    field(:needs_intervention, boolean(), default: false)
    field(:convergence_risk, float(), default: 0.0)       # 0.0-1.0

    field(:computed_at, integer(), enforce: true)
    field(:metadata, map(), default: %{})
  end

  typedstruct module: DiversityConfig do
    @moduledoc """
    Configuration for diversity enforcement.
    """

    # Similarity detection
    field(:similarity_strategy, similarity_strategy(), default: :composite)
    field(:duplicate_threshold, float(), default: 0.95)   # Consider duplicates if similarity > this
    field(:similar_threshold, float(), default: 0.85)     # Consider similar if > this

    # Diversity thresholds
    field(:min_diversity, float(), default: 0.3)          # Trigger intervention if below
    field(:target_diversity, float(), default: 0.6)       # Healthy diversity level
    field(:max_similarity, float(), default: 0.8)         # Max avg similarity before intervention

    # Intervention strategies
    field(:enable_promotion, boolean(), default: true)
    field(:enable_novelty_rewards, boolean(), default: true)
    field(:promotion_strategy, :random | :targeted | :adaptive, default: :adaptive)

    # Novelty archive
    field(:archive_size, pos_integer(), default: 50)
    field(:novelty_k_nearest, pos_integer(), default: 15)

    field(:metadata, map(), default: %{})
  end

  typedstruct module: NoveltyScore do
    @moduledoc """
    Novelty score for a prompt relative to population and archive.
    """

    field(:prompt_id, String.t(), enforce: true)
    field(:novelty_score, float(), enforce: true)         # Higher = more novel
    field(:k_nearest_distances, list(float()), default: [])
    field(:behavioral_signature, map(), default: %{})
    field(:archive_comparison, map(), default: %{})
    field(:computed_at, integer(), enforce: true)
    field(:metadata, map(), default: %{})
  end

  typedstruct module: DiversityReport do
    @moduledoc """
    Comprehensive report on population diversity.
    """

    field(:population_id, String.t(), enforce: true)
    field(:generation, non_neg_integer(), enforce: true)
    field(:metrics, DiversityMetrics.t(), enforce: true)
    field(:similarity_matrix, SimilarityMatrix.t(), enforce: true)
    field(:novelty_scores, list(NoveltyScore.t()), default: [])

    # Recommendations
    field(:requires_intervention, boolean(), default: false)
    field(:recommended_actions, list(atom()), default: [])
    field(:convergence_warning, String.t() | nil)

    field(:generated_at, integer(), enforce: true)
  end
end
```

### Module Responsibilities

#### 1. SimilarityDetector (Subtask 1.4.3.1)

**Purpose**: Identify duplicate and near-duplicate prompts using multiple similarity strategies.

**Key Functions**:
```elixir
@spec detect_similarities(Population.t(), DiversityConfig.t()) ::
  {:ok, SimilarityMatrix.t()} | {:error, term()}
def detect_similarities(population, config)

@spec compare_prompts(String.t(), String.t(), similarity_strategy()) ::
  {:ok, SimilarityResult.t()} | {:error, term()}
def compare_prompts(prompt_a, prompt_b, strategy)

@spec find_near_duplicates(SimilarityMatrix.t(), float()) ::
  list({String.t(), String.t()})
def find_near_duplicates(matrix, threshold)

@spec build_similarity_matrix(list(Population.Candidate.t()), DiversityConfig.t()) ::
  {:ok, SimilarityMatrix.t()} | {:error, term()}
defp build_similarity_matrix(candidates, config)
```

**Similarity Strategies**:

1. **Text Similarity** (`text_similarity.ex`):
   ```elixir
   # Levenshtein distance (edit distance)
   def levenshtein_similarity(text_a, text_b) do
     distance = String.jaro_distance(text_a, text_b)
     distance  # 0.0-1.0, higher = more similar
   end

   # Jaccard similarity (token overlap)
   def jaccard_similarity(text_a, text_b) do
     tokens_a = tokenize(text_a) |> MapSet.new()
     tokens_b = tokenize(text_b) |> MapSet.new()
     intersection = MapSet.intersection(tokens_a, tokens_b) |> MapSet.size()
     union = MapSet.union(tokens_a, tokens_b) |> MapSet.size()
     intersection / union
   end

   # Character n-gram similarity
   def ngram_similarity(text_a, text_b, n \\ 3) do
     ngrams_a = generate_ngrams(text_a, n) |> MapSet.new()
     ngrams_b = generate_ngrams(text_b, n) |> MapSet.new()
     intersection = MapSet.intersection(ngrams_a, ngrams_b) |> MapSet.size()
     union = MapSet.union(ngrams_a, ngrams_b) |> MapSet.size()
     intersection / union
   end

   # Composite text similarity
   def composite_text_similarity(text_a, text_b) do
     jaro = String.jaro_distance(text_a, text_b)
     jaccard = jaccard_similarity(text_a, text_b)
     ngram = ngram_similarity(text_a, text_b, 3)

     # Weighted combination
     (jaro * 0.4) + (jaccard * 0.3) + (ngram * 0.3)
   end
   ```

2. **Structural Similarity** (`structural_similarity.ex`):
   ```elixir
   # Segment-based similarity (reuses Crossover segmentation)
   def segment_similarity(prompt_a, prompt_b) do
     {:ok, seg_a} = Crossover.Segmenter.segment(prompt_a)
     {:ok, seg_b} = Crossover.Segmenter.segment(prompt_b)

     # Compare segment types and counts
     type_similarity = segment_type_overlap(seg_a, seg_b)
     count_similarity = segment_count_similarity(seg_a, seg_b)
     structure_similarity = structure_type_match(seg_a, seg_b)

     (type_similarity * 0.4) + (count_similarity * 0.3) + (structure_similarity * 0.3)
   end

   defp segment_type_overlap(seg_a, seg_b) do
     types_a = Enum.map(seg_a.segments, & &1.type) |> MapSet.new()
     types_b = Enum.map(seg_b.segments, & &1.type) |> MapSet.new()
     intersection = MapSet.intersection(types_a, types_b) |> MapSet.size()
     union = MapSet.union(types_a, types_b) |> MapSet.size()
     if union > 0, do: intersection / union, else: 0.0
   end
   ```

3. **Semantic Similarity** (`semantic_similarity.ex`):
   ```elixir
   # Embedding-based similarity (expensive, optional)
   # Note: Requires embedding provider integration
   def embedding_similarity(prompt_a, prompt_b, provider) do
     # Generate embeddings via LLM
     {:ok, embedding_a} = generate_embedding(prompt_a, provider)
     {:ok, embedding_b} = generate_embedding(prompt_b, provider)

     # Cosine similarity
     cosine_similarity(embedding_a, embedding_b)
   end

   defp cosine_similarity(vec_a, vec_b) do
     dot_product = Enum.zip(vec_a, vec_b)
       |> Enum.reduce(0.0, fn {a, b}, acc -> acc + (a * b) end)

     magnitude_a = :math.sqrt(Enum.reduce(vec_a, 0.0, fn x, acc -> acc + x * x end))
     magnitude_b = :math.sqrt(Enum.reduce(vec_b, 0.0, fn x, acc -> acc + x * x end))

     dot_product / (magnitude_a * magnitude_b)
   end
   ```

4. **Behavioral Similarity** (`behavioral_similarity.ex`):
   ```elixir
   # Compare execution trajectories (expensive)
   def trajectory_similarity(trajectory_a, trajectory_b) do
     # Use existing TrajectoryAnalyzer
     pattern_a = TrajectoryAnalyzer.extract_pattern(trajectory_a)
     pattern_b = TrajectoryAnalyzer.extract_pattern(trajectory_b)

     # Compare reasoning steps
     step_similarity = compare_steps(pattern_a.steps, pattern_b.steps)

     # Compare outcomes
     outcome_similarity = compare_outcomes(pattern_a.result, pattern_b.result)

     # Compare tool usage patterns
     tool_similarity = compare_tool_usage(pattern_a.actions, pattern_b.actions)

     (step_similarity * 0.4) + (outcome_similarity * 0.3) + (tool_similarity * 0.3)
   end
   ```

5. **Composite Similarity** (default):
   ```elixir
   def composite_similarity(prompt_a, prompt_b, config) do
     # Fast text-based similarity (always computed)
     text_sim = TextSimilarity.composite_text_similarity(prompt_a, prompt_b)

     # Structural similarity (moderately expensive)
     struct_sim = StructuralSimilarity.segment_similarity(prompt_a, prompt_b)

     # Semantic similarity (expensive, optional)
     semantic_sim =
       if config.use_semantic_similarity do
         SemanticSimilarity.embedding_similarity(prompt_a, prompt_b, config.provider)
       else
         0.0
       end

     # Behavioral similarity (very expensive, only for critical comparisons)
     behavioral_sim =
       if config.use_behavioral_similarity do
         # Requires trajectory data
         BehavioralSimilarity.trajectory_similarity(trajectory_a, trajectory_b)
       else
         0.0
       end

     # Weighted composite
     weights = config.similarity_weights || %{
       text: 0.4,
       structural: 0.3,
       semantic: 0.2,
       behavioral: 0.1
     }

     (text_sim * weights.text) +
       (struct_sim * weights.structural) +
       (semantic_sim * weights.semantic) +
       (behavioral_sim * weights.behavioral)
   end
   ```

**Complexity Analysis**:
- Text similarity: O(n*m) where n, m are prompt lengths (Levenshtein)
- Structural similarity: O(s1*s2) where s1, s2 are segment counts
- Semantic similarity: O(1) comparison after O(n) embedding generation
- Building full matrix: O(P²) where P is population size

For population of 50 prompts: ~1,225 comparisons

**Optimization Strategy**:
- Use cheap text similarity as filter (eliminate obviously different prompts)
- Apply expensive semantic similarity only to borderline cases
- Cache similarity results between generations (prompts don't change)
- Parallel comparison using Task.async_stream

---

#### 2. DiversityMetrics (Subtask 1.4.3.2)

**Purpose**: Quantify population-level variation using multiple diversity measures.

**Key Functions**:
```elixir
@spec calculate_metrics(Population.t(), SimilarityMatrix.t(), DiversityConfig.t()) ::
  {:ok, DiversityMetrics.t()} | {:error, term()}
def calculate_metrics(population, similarity_matrix, config)

@spec assess_diversity_level(DiversityMetrics.t(), DiversityConfig.t()) ::
  diversity_level()
def assess_diversity_level(metrics, config)

@spec detect_convergence_risk(DiversityMetrics.t(), list(DiversityMetrics.t())) ::
  float()
def detect_convergence_risk(current_metrics, historical_metrics)

@spec generate_report(Population.t(), DiversityConfig.t()) ::
  {:ok, DiversityReport.t()} | {:error, term()}
def generate_report(population, config)
```

**Diversity Metrics**:

1. **Pairwise Diversity** (average distance between all prompt pairs):
   ```elixir
   def pairwise_diversity(similarity_matrix) do
     # Average dissimilarity
     total_dissimilarity =
       similarity_matrix.similarities
       |> Map.values()
       |> Enum.reduce(0.0, fn result, acc ->
         acc + (1.0 - result.similarity_score)
       end)

     count = map_size(similarity_matrix.similarities)
     if count > 0, do: total_dissimilarity / count, else: 0.0
   end
   ```

2. **Entropy** (Shannon entropy of prompt features):
   ```elixir
   def feature_entropy(population) do
     # Extract features (tokens, segment types, structural patterns)
     features = extract_features(population)

     # Calculate frequency distribution
     feature_counts = Enum.frequencies(features)
     total = Enum.sum(Map.values(feature_counts))

     # Shannon entropy: -Σ(p * log2(p))
     feature_counts
     |> Enum.reduce(0.0, fn {_feature, count}, acc ->
       p = count / total
       acc - (p * :math.log2(p))
     end)
   end
   ```

3. **Coverage** (portion of search space explored):
   ```elixir
   def search_space_coverage(population, config) do
     # Approximate coverage using prompt characteristics
     # - Length diversity: range of prompt lengths
     # - Type diversity: variety of segment types used
     # - Structural diversity: different prompt structures

     length_coverage = length_diversity(population)
     type_coverage = segment_type_coverage(population)
     structure_coverage = structure_diversity(population)

     (length_coverage + type_coverage + structure_coverage) / 3.0
   end

   defp length_diversity(population) do
     lengths = Enum.map(population.candidates, fn {_id, c} ->
       String.length(c.prompt)
     end)

     min_len = Enum.min(lengths)
     max_len = Enum.max(lengths)
     avg_len = Enum.sum(lengths) / length(lengths)

     # Normalized range
     if max_len > 0 do
       (max_len - min_len) / avg_len
     else
       0.0
     end
   end
   ```

4. **Unique Ratio** (fraction of unique prompts):
   ```elixir
   def unique_ratio(population) do
     prompts = Enum.map(population.candidates, fn {_id, c} -> c.prompt end)
     unique_count = prompts |> Enum.uniq() |> length()
     total_count = length(prompts)

     if total_count > 0, do: unique_count / total_count, else: 1.0
   end
   ```

5. **Clustering Analysis** (identify distinct groups):
   ```elixir
   def cluster_analysis(similarity_matrix, threshold \\ 0.75) do
     # Simple hierarchical clustering
     # Group prompts with similarity > threshold
     clusters = build_clusters(similarity_matrix, threshold)

     %{
       cluster_count: length(clusters),
       largest_cluster_size: largest_cluster_size(clusters),
       cluster_sizes: Enum.map(clusters, &length/1),
       cluster_balance: cluster_balance_score(clusters)
     }
   end

   defp build_clusters(similarity_matrix, threshold) do
     # Union-find / connected components approach
     # Two prompts in same cluster if similarity > threshold
     # Returns list of clusters (each cluster is list of prompt IDs)
     # Implementation details...
   end
   ```

6. **Convergence Risk** (predict premature convergence):
   ```elixir
   def convergence_risk(current_metrics, historical_metrics) do
     # Analyze diversity trend over generations
     diversity_trend = calculate_trend(historical_metrics)

     # Risk factors:
     # 1. Rapid diversity decline
     # 2. High average similarity
     # 3. Large dominant cluster
     # 4. Low entropy

     decline_risk = if diversity_trend < -0.1, do: 0.3, else: 0.0
     similarity_risk = if current_metrics.avg_similarity > 0.8, do: 0.3, else: 0.0
     cluster_risk = if current_metrics.largest_cluster_size > population_size * 0.5, do: 0.3, else: 0.0
     entropy_risk = if current_metrics.entropy < 2.0, do: 0.1, else: 0.0

     min(1.0, decline_risk + similarity_risk + cluster_risk + entropy_risk)
   end
   ```

**Diversity Level Assessment**:
```elixir
def assess_diversity_level(metrics, config) do
  cond do
    metrics.pairwise_diversity < config.min_diversity * 0.5 ->
      :critical

    metrics.pairwise_diversity < config.min_diversity ->
      :low

    metrics.pairwise_diversity < config.target_diversity ->
      :moderate

    metrics.pairwise_diversity < config.target_diversity * 1.5 ->
      :healthy

    true ->
      :excellent
  end
end
```

---

#### 3. DiversityPromoter (Subtask 1.4.3.3)

**Purpose**: Increase variation when population becomes homogeneous.

**Key Functions**:
```elixir
@spec promote_diversity(Population.t(), DiversityMetrics.t(), DiversityConfig.t()) ::
  {:ok, Population.t()} | {:error, term()}
def promote_diversity(population, metrics, config)

@spec inject_random_variations(Population.t(), pos_integer()) ::
  {:ok, Population.t()} | {:error, term()}
def inject_random_variations(population, count)

@spec increase_mutation_rate(float(), DiversityMetrics.t()) :: float()
def increase_mutation_rate(current_rate, metrics)

@spec targeted_diversification(Population.t(), SimilarityMatrix.t()) ::
  {:ok, Population.t()} | {:error, term()}
def targeted_diversification(population, similarity_matrix)
```

**Promotion Strategies**:

1. **Random Injection**:
   ```elixir
   def inject_random_variations(population, count) do
     # Generate count new random prompts
     # Replace lowest-fitness candidates if population at capacity

     new_prompts = generate_random_prompts(count, population)

     # Add to population (may replace worst performers)
     Enum.reduce(new_prompts, {:ok, population}, fn prompt, {:ok, pop} ->
       candidate = %{
         prompt: prompt,
         fitness: nil,
         metadata: %{source: :diversity_injection, injected_at: System.monotonic_time()}
       }
       Population.add_candidate(pop, candidate)
     end)
   end

   defp generate_random_prompts(count, population) do
     # Use mutation operators with high randomness
     # Sample from best prompts and apply aggressive mutations
     best = Population.get_best(population, limit: 5)

     for _i <- 1..count do
       base = Enum.random(best)
       mutate_aggressively(base.prompt)
     end
   end

   defp mutate_aggressively(prompt) do
     # Apply multiple random mutations
     # Use high mutation rates
     # Combine different mutation types

     prompt
     |> maybe_add_random_instruction(0.7)
     |> maybe_delete_random_section(0.3)
     |> maybe_replace_with_synonym(0.5)
     |> maybe_reorder_sections(0.4)
   end
   ```

2. **Adaptive Mutation Rate**:
   ```elixir
   def increase_mutation_rate(current_rate, metrics) do
     # Increase mutation rate when diversity is low
     # Decrease when diversity is high

     target_diversity = 0.6
     current_diversity = metrics.pairwise_diversity

     diversity_gap = target_diversity - current_diversity

     cond do
       diversity_gap > 0.3 ->
         # Critical: increase aggressively
         min(1.0, current_rate * 2.0)

       diversity_gap > 0.15 ->
         # Low: moderate increase
         min(1.0, current_rate * 1.5)

       diversity_gap > 0.05 ->
         # Slightly low: gentle increase
         min(1.0, current_rate * 1.2)

       diversity_gap < -0.15 ->
         # Too diverse: decrease
         max(0.1, current_rate * 0.8)

       true ->
         # Healthy: maintain
         current_rate
     end
   end
   ```

3. **Targeted Diversification**:
   ```elixir
   def targeted_diversification(population, similarity_matrix) do
     # Identify overly similar prompts
     similar_pairs = find_similar_pairs(similarity_matrix, threshold: 0.85)

     # For each similar pair, mutate one to increase distance
     Enum.reduce(similar_pairs, {:ok, population}, fn {id_a, id_b}, {:ok, pop} ->
       # Mutate the lower-fitness one
       {:ok, candidate_a} = Population.get_candidate(pop, id_a)
       {:ok, candidate_b} = Population.get_candidate(pop, id_b)

       to_mutate =
         if (candidate_a.fitness || 0.0) < (candidate_b.fitness || 0.0) do
           candidate_a
         else
           candidate_b
         end

       # Apply diversifying mutation
       {:ok, mutated} = diversify_prompt(to_mutate, [candidate_a, candidate_b])

       # Replace in population
       Population.replace_candidate(pop, to_mutate.id, mutated)
     end)
   end

   defp diversify_prompt(candidate, similar_prompts) do
     # Mutate to maximize distance from similar prompts
     # Try multiple mutations, select one that increases diversity most

     similar_texts = Enum.map(similar_prompts, & &1.prompt)

     candidate.prompt
     |> generate_diverse_mutations(count: 5)
     |> select_most_diverse(similar_texts)
   end

   defp generate_diverse_mutations(prompt, opts) do
     count = Keyword.get(opts, :count, 5)

     # Generate multiple mutation variants
     for _i <- 1..count do
       # Use random mutation strategy
       Mutation.Orchestrator.mutate(prompt, strategy: Enum.random([
         :edit, :addition, :deletion, :replacement
       ]))
     end
   end

   defp select_most_diverse(mutations, similar_prompts) do
     # Select mutation that maximizes distance from similar prompts
     Enum.max_by(mutations, fn mutated ->
       avg_distance =
         similar_prompts
         |> Enum.map(fn similar ->
           {:ok, result} = TextSimilarity.composite_text_similarity(mutated, similar)
           1.0 - result  # Convert similarity to distance
         end)
         |> Enum.sum()
         |> then(& &1 / length(similar_prompts))

       avg_distance
     end)
   end
   ```

4. **Archive-Based Seeding**:
   ```elixir
   def seed_from_archive(population, archive, config) do
     # If population too homogeneous, inject diverse prompts from archive
     # Archive contains historically successful diverse prompts

     # Select diverse archive members
     diverse_candidates = select_diverse_from_archive(archive, count: 5)

     # Add to population
     Enum.reduce(diverse_candidates, {:ok, population}, fn archived, {:ok, pop} ->
       candidate = %{
         prompt: archived.prompt,
         fitness: nil,
         parent_ids: [],
         metadata: %{source: :archive_seeding, original_generation: archived.generation}
       }
       Population.add_candidate(pop, candidate)
     end)
   end
   ```

---

#### 4. NoveltyScorer (Subtask 1.4.3.4)

**Purpose**: Encourage exploration of new approaches by rewarding behavioral novelty.

**Key Functions**:
```elixir
@spec calculate_novelty(Population.Candidate.t(), Population.t(), Archive.t(), DiversityConfig.t()) ::
  {:ok, NoveltyScore.t()} | {:error, term()}
def calculate_novelty(candidate, population, archive, config)

@spec behavioral_characterization(Trajectory.t()) :: map()
def behavioral_characterization(trajectory)

@spec k_nearest_novelty(map(), list(map()), pos_integer()) :: float()
def k_nearest_novelty(behavior, archive_behaviors, k)

@spec combine_fitness_and_novelty(float(), float(), float()) :: float()
def combine_fitness_and_novelty(fitness, novelty, novelty_weight)
```

**Novelty Search Implementation**:

1. **Behavioral Characterization**:
   ```elixir
   def behavioral_characterization(trajectory) do
     # Extract behavioral descriptor from execution trajectory
     # Captures WHAT the prompt does, not just fitness

     %{
       # Reasoning characteristics
       step_count: length(trajectory.steps),
       reasoning_depth: calculate_depth(trajectory.steps),
       reasoning_patterns: extract_patterns(trajectory.steps),

       # Tool usage
       tool_calls: count_tool_calls(trajectory),
       tool_diversity: unique_tools_used(trajectory),

       # Output characteristics
       output_type: classify_output_type(trajectory.result),
       output_length: output_length(trajectory.result),

       # Error handling
       error_count: count_errors(trajectory),
       recovery_attempts: count_recovery_attempts(trajectory),

       # Semantic features (if available)
       key_concepts: extract_key_concepts(trajectory),
       approach_type: classify_approach(trajectory)
     }
   end

   defp calculate_depth(steps) do
     # Measure reasoning depth (nested thoughts, sub-goals)
     max_depth = steps
       |> Enum.map(& &1.depth || 0)
       |> Enum.max(fn -> 0 end)

     max_depth
   end

   defp extract_patterns(steps) do
     # Identify reasoning patterns
     # Examples: "systematic", "exploratory", "analytical", "creative"
     steps
     |> Enum.map(&classify_step/1)
     |> Enum.frequencies()
   end
   ```

2. **K-Nearest Novelty Scoring**:
   ```elixir
   def k_nearest_novelty(behavior, archive_behaviors, k) do
     # Calculate distance to k nearest neighbors in behavior space
     # Higher distance = more novel

     distances =
       archive_behaviors
       |> Enum.map(fn archive_behavior ->
         behavioral_distance(behavior, archive_behavior)
       end)
       |> Enum.sort()
       |> Enum.take(k)

     # Average distance to k nearest neighbors
     if length(distances) > 0 do
       Enum.sum(distances) / length(distances)
     else
       # No archive yet, maximum novelty
       1.0
     end
   end

   defp behavioral_distance(behavior_a, behavior_b) do
     # Multi-dimensional distance in behavior space
     # Weighted Euclidean distance across behavioral features

     step_diff = abs(behavior_a.step_count - behavior_b.step_count) / 10.0
     depth_diff = abs(behavior_a.reasoning_depth - behavior_b.reasoning_depth) / 5.0
     tool_diff = abs(behavior_a.tool_diversity - behavior_b.tool_diversity) / 5.0
     pattern_diff = pattern_distance(behavior_a.reasoning_patterns, behavior_b.reasoning_patterns)

     :math.sqrt(
       step_diff * step_diff +
       depth_diff * depth_diff +
       tool_diff * tool_diff +
       pattern_diff * pattern_diff
     )
   end

   defp pattern_distance(patterns_a, patterns_b) do
     # Cosine distance between pattern frequency vectors
     all_patterns = Map.keys(patterns_a) ++ Map.keys(patterns_b)
       |> Enum.uniq()

     vec_a = Enum.map(all_patterns, fn p -> Map.get(patterns_a, p, 0) end)
     vec_b = Enum.map(all_patterns, fn p -> Map.get(patterns_b, p, 0) end)

     1.0 - cosine_similarity(vec_a, vec_b)
   end
   ```

3. **Fitness-Novelty Combination**:
   ```elixir
   def combine_fitness_and_novelty(fitness, novelty, novelty_weight \\ 0.3) do
     # Combine quality (fitness) and diversity (novelty)
     # novelty_weight: 0.0 = pure fitness, 1.0 = pure novelty

     # Normalize both to 0-1 range if needed
     normalized_fitness = normalize_fitness(fitness)
     normalized_novelty = normalize_novelty(novelty)

     # Weighted combination
     (normalized_fitness * (1.0 - novelty_weight)) +
       (normalized_novelty * novelty_weight)
   end

   # Adaptive novelty weight based on diversity
   def adaptive_novelty_weight(diversity_metrics) do
     # Increase novelty weight when diversity is low
     # Decrease when diversity is healthy

     cond do
       diversity_metrics.diversity_level == :critical ->
         0.6  # Heavy emphasis on novelty

       diversity_metrics.diversity_level == :low ->
         0.4  # Moderate novelty emphasis

       diversity_metrics.diversity_level == :moderate ->
         0.3  # Balanced

       diversity_metrics.diversity_level == :healthy ->
         0.2  # Focus more on fitness

       diversity_metrics.diversity_level == :excellent ->
         0.1  # Minimal novelty bonus
     end
   end
   ```

4. **Novelty Archive Management**:
   ```elixir
   defmodule Jido.AI.Runner.GEPA.Diversity.NoveltyArchive do
     use GenServer

     @moduledoc """
     Maintains archive of behaviorally diverse solutions for novelty comparison.
     """

     def start_link(opts) do
       GenServer.start_link(__MODULE__, opts, name: __MODULE__)
     end

     def add_to_archive(candidate, behavior, fitness) do
       GenServer.call(__MODULE__, {:add, candidate, behavior, fitness})
     end

     def get_archive() do
       GenServer.call(__MODULE__, :get_archive)
     end

     # Implementation
     def init(opts) do
       max_size = Keyword.get(opts, :max_size, 50)
       {:ok, %{archive: [], max_size: max_size}}
     end

     def handle_call({:add, candidate, behavior, fitness}, _from, state) do
       # Add to archive if:
       # 1. Archive not full, OR
       # 2. Candidate is more novel than least novel in archive

       updated_archive =
         if length(state.archive) < state.max_size do
           # Archive has space
           [%{candidate: candidate, behavior: behavior, fitness: fitness} | state.archive]
         else
           # Archive full, check if should replace
           maybe_replace_in_archive(state.archive, candidate, behavior, fitness)
         end

       {:reply, :ok, %{state | archive: updated_archive}}
     end

     def handle_call(:get_archive, _from, state) do
       {:reply, state.archive, state}
     end

     defp maybe_replace_in_archive(archive, new_candidate, new_behavior, new_fitness) do
       # Calculate novelty of new candidate relative to archive
       archive_behaviors = Enum.map(archive, & &1.behavior)
       new_novelty = k_nearest_novelty(new_behavior, archive_behaviors, 15)

       # Find least novel in archive
       {least_novel, _novelty} =
         archive
         |> Enum.map(fn entry ->
           others = Enum.reject(archive_behaviors, &(&1 == entry.behavior))
           novelty = k_nearest_novelty(entry.behavior, others, 15)
           {entry, novelty}
         end)
         |> Enum.min_by(fn {_entry, novelty} -> novelty end)

       # Replace if new is more novel
       if new_novelty > least_novel.novelty do
         archive
         |> Enum.reject(&(&1 == least_novel))
         |> then(fn arch ->
           [%{candidate: new_candidate, behavior: new_behavior, fitness: new_fitness} | arch]
         end)
       else
         archive
       end
     end
   end
   ```

---

### Integration with Existing Systems

#### Population Module Extension

Extend `Population` struct with diversity tracking:

```elixir
# In lib/jido_ai/runner/gepa/population.ex

# Add to Population struct:
field(:diversity_metrics, DiversityMetrics.t() | nil)
field(:diversity_history, list(DiversityMetrics.t()), default: [])
field(:novelty_archive, list(map()), default: [])

# New functions:

@spec update_diversity_metrics(t(), DiversityMetrics.t()) :: t()
def update_diversity_metrics(population, metrics) do
  history = [metrics | population.diversity_history] |> Enum.take(20)  # Keep last 20

  %{population |
    diversity_metrics: metrics,
    diversity_history: history,
    updated_at: System.monotonic_time(:millisecond)
  }
end

@spec requires_diversity_intervention?(t(), DiversityConfig.t()) :: boolean()
def requires_diversity_intervention?(population, config) do
  case population.diversity_metrics do
    nil ->
      false

    metrics ->
      metrics.needs_intervention or
        metrics.pairwise_diversity < config.min_diversity or
        metrics.convergence_risk > 0.7
  end
end
```

#### Optimizer Integration

In the main GEPA optimizer loop:

```elixir
# In lib/jido_ai/runner/gepa/optimizer.ex

defp evolution_cycle(state) do
  # 1. Evaluate population
  {:ok, evaluated_pop} = evaluate_population(state.population)

  # 2. Check diversity (NEW)
  {:ok, diversity_report} = Diversity.Metrics.generate_report(
    evaluated_pop,
    state.config.diversity_config
  )

  # 3. Update population with diversity metrics (NEW)
  pop_with_diversity = Population.update_diversity_metrics(
    evaluated_pop,
    diversity_report.metrics
  )

  # 4. Diversity intervention if needed (NEW)
  pop_after_intervention =
    if Population.requires_diversity_intervention?(pop_with_diversity, state.config.diversity_config) do
      Logger.info("Diversity intervention triggered",
        level: diversity_report.metrics.diversity_level,
        pairwise_diversity: diversity_report.metrics.pairwise_diversity
      )

      {:ok, promoted_pop} = Diversity.Promoter.promote_diversity(
        pop_with_diversity,
        diversity_report.metrics,
        state.config.diversity_config
      )

      promoted_pop
    else
      pop_with_diversity
    end

  # 5. Selection (use novelty scores if available)
  {:ok, selected} = select_parents(pop_after_intervention, diversity_report)

  # 6. Crossover
  {:ok, offspring} = perform_crossover(selected)

  # 7. Mutation (with adaptive rate based on diversity)
  mutation_rate = calculate_adaptive_mutation_rate(
    state.config.mutation_rate,
    diversity_report.metrics
  )

  {:ok, mutated} = mutate_offspring(offspring, mutation_rate)

  # 8. Create next generation
  {:ok, next_pop} = create_next_generation(pop_after_intervention, mutated)

  # 9. Update novelty archive (NEW)
  update_novelty_archive(next_pop, diversity_report)

  {:ok, %{state | population: next_pop, generation: state.generation + 1}}
end

defp calculate_adaptive_mutation_rate(base_rate, diversity_metrics) do
  Diversity.Promoter.increase_mutation_rate(base_rate, diversity_metrics)
end

defp select_parents(population, diversity_report) do
  # Use fitness + novelty for selection
  candidates_with_scores =
    population
    |> Population.get_all()
    |> Enum.map(fn candidate ->
      novelty_score = find_novelty_score(candidate.id, diversity_report.novelty_scores)
      combined_score = Diversity.NoveltyScorer.combine_fitness_and_novelty(
        candidate.fitness || 0.0,
        novelty_score || 0.0,
        diversity_report.metrics.convergence_risk * 0.5  # Adaptive novelty weight
      )

      {candidate, combined_score}
    end)
    |> Enum.sort_by(fn {_c, score} -> score end, :desc)

  # Tournament selection using combined scores
  # ...
end
```

---

## Implementation Plan

### Phase 1: Similarity Detection (Subtask 1.4.3.1)

**Goal**: Implement robust similarity detection using multiple strategies.

#### Step 1.1: Text-Based Similarity

**File**: `lib/jido_ai/runner/gepa/diversity/strategies/text_similarity.ex`

**Tasks**:
1. Implement `levenshtein_similarity/2` using String.jaro_distance
2. Implement `jaccard_similarity/2` with token-based comparison
3. Implement `ngram_similarity/3` with configurable n-gram size
4. Implement `composite_text_similarity/2` combining all three

**Tests**:
- Identical strings (similarity = 1.0)
- Completely different strings (similarity ≈ 0.0)
- Similar strings with minor edits (similarity > 0.8)
- Strings with word reordering (Jaccard higher than Levenshtein)
- Different lengths (edge cases)

**Deliverables**:
- [ ] Text similarity implementation
- [ ] Comprehensive unit tests (20+ test cases)
- [ ] Performance tests (1000+ comparisons)
- [ ] Documentation

---

#### Step 1.2: Structural Similarity

**File**: `lib/jido_ai/runner/gepa/diversity/strategies/structural_similarity.ex`

**Tasks**:
1. Reuse Crossover.Segmenter for prompt segmentation
2. Implement `segment_type_overlap/2`
3. Implement `segment_count_similarity/2`
4. Implement `structure_type_match/2`
5. Implement composite `segment_similarity/2`

**Tests**:
- Prompts with identical structure (high similarity)
- Prompts with different segment types (low similarity)
- Prompts with same types, different content (moderate similarity)
- Edge cases (single segment, many segments)

**Deliverables**:
- [ ] Structural similarity implementation
- [ ] Integration with Crossover.Segmenter
- [ ] Unit tests
- [ ] Documentation

---

#### Step 1.3: Similarity Detector Core

**File**: `lib/jido_ai/runner/gepa/diversity/similarity_detector.ex`

**Tasks**:
1. Implement `compare_prompts/3` with strategy selection
2. Implement `detect_similarities/2` building full matrix
3. Implement `find_near_duplicates/2` identifying similar pairs
4. Add caching for repeated comparisons
5. Add parallel processing using Task.async_stream

**Tests**:
- Compare two prompts with different strategies
- Build similarity matrix for small population (10 prompts)
- Build similarity matrix for larger population (50 prompts)
- Find near-duplicates with various thresholds
- Performance test (O(n²) scaling)
- Cache hit verification

**Deliverables**:
- [ ] SimilarityDetector implementation
- [ ] SimilarityResult and SimilarityMatrix structs
- [ ] Parallel processing
- [ ] Unit and integration tests
- [ ] Documentation

---

### Phase 2: Diversity Metrics (Subtask 1.4.3.2)

**Goal**: Quantify population diversity using multiple measures.

#### Step 2.1: Core Diversity Metrics

**File**: `lib/jido_ai/runner/gepa/diversity/metrics.ex`

**Tasks**:
1. Implement `pairwise_diversity/1` from similarity matrix
2. Implement `feature_entropy/1` with Shannon entropy
3. Implement `search_space_coverage/2` with multi-dimensional coverage
4. Implement `unique_ratio/1`
5. Implement `cluster_analysis/2` with hierarchical clustering

**Tests**:
- Uniform population (low diversity)
- Highly diverse population (high diversity)
- Mixed population (moderate diversity)
- Entropy calculation for various distributions
- Clustering with different thresholds
- Edge cases (empty, single candidate)

**Deliverables**:
- [ ] Core diversity metrics
- [ ] DiversityMetrics struct
- [ ] Unit tests
- [ ] Performance benchmarks
- [ ] Documentation

---

#### Step 2.2: Diversity Assessment

**Tasks**:
1. Implement `assess_diversity_level/2`
2. Implement `detect_convergence_risk/2` with trend analysis
3. Implement `generate_report/2` creating comprehensive report

**Tests**:
- Assess various diversity levels
- Detect convergence from historical data
- Generate report for different populations
- Verify threshold-based classification
- Test convergence risk factors

**Deliverables**:
- [ ] Diversity assessment functions
- [ ] DiversityReport struct
- [ ] Unit tests
- [ ] Documentation

---

#### Step 2.3: Population Integration

**File**: `lib/jido_ai/runner/gepa/population.ex` (extend existing)

**Tasks**:
1. Add diversity_metrics field to Population struct
2. Add diversity_history field
3. Implement `update_diversity_metrics/2`
4. Implement `requires_diversity_intervention?/2`

**Tests**:
- Update diversity metrics
- Track diversity history
- Intervention triggering logic
- Edge cases

**Deliverables**:
- [ ] Extended Population module
- [ ] Migration for existing code
- [ ] Tests
- [ ] Documentation

---

### Phase 3: Diversity-Promoting Mutation (Subtask 1.4.3.3)

**Goal**: Increase variation when population becomes homogeneous.

#### Step 3.1: Promotion Strategies

**File**: `lib/jido_ai/runner/gepa/diversity/promoter.ex`

**Tasks**:
1. Implement `inject_random_variations/2`
   - Random prompt generation
   - Replace worst performers
2. Implement `increase_mutation_rate/2`
   - Adaptive rate calculation
   - Smooth transitions
3. Implement `targeted_diversification/2`
   - Identify similar pairs
   - Mutate to maximize distance
4. Implement main `promote_diversity/3` coordinator

**Tests**:
- Random injection with various counts
- Mutation rate adaptation based on diversity levels
- Targeted diversification increasing distance
- Full promotion workflow
- Edge cases (empty population, already diverse)

**Deliverables**:
- [ ] DiversityPromoter implementation
- [ ] All promotion strategies
- [ ] Unit tests
- [ ] Integration tests
- [ ] Documentation

---

#### Step 3.2: Aggressive Mutation Utilities

**Tasks**:
1. Implement `mutate_aggressively/1`
2. Implement `generate_diverse_mutations/2`
3. Implement `select_most_diverse/2`

**Tests**:
- Aggressive mutation produces substantial changes
- Diverse mutations are sufficiently different
- Selection maximizes distance from targets

**Deliverables**:
- [ ] Mutation utilities
- [ ] Tests
- [ ] Documentation

---

### Phase 4: Novelty Rewards (Subtask 1.4.3.4)

**Goal**: Encourage exploration through behavioral novelty scoring.

#### Step 4.1: Behavioral Characterization

**File**: `lib/jido_ai/runner/gepa/diversity/novelty_scorer.ex`

**Tasks**:
1. Implement `behavioral_characterization/1`
   - Step count and depth
   - Tool usage patterns
   - Output characteristics
   - Error patterns
2. Implement `behavioral_distance/2`
   - Multi-dimensional distance
   - Weighted features

**Tests**:
- Characterize various trajectory types
- Distance calculation for similar behaviors
- Distance calculation for different behaviors
- Edge cases (empty trajectory, errors)

**Deliverables**:
- [ ] Behavioral characterization
- [ ] Distance calculation
- [ ] Unit tests
- [ ] Documentation

---

#### Step 4.2: Novelty Scoring

**Tasks**:
1. Implement `k_nearest_novelty/3`
2. Implement `calculate_novelty/4` main function
3. Implement `combine_fitness_and_novelty/3`
4. Implement `adaptive_novelty_weight/1`

**Tests**:
- K-nearest calculation with various k values
- Novelty scoring for novel vs. common behaviors
- Fitness-novelty combination with various weights
- Adaptive weight based on diversity levels

**Deliverables**:
- [ ] Novelty scoring implementation
- [ ] NoveltyScore struct
- [ ] Unit tests
- [ ] Documentation

---

#### Step 4.3: Novelty Archive

**File**: `lib/jido_ai/runner/gepa/diversity/novelty_archive.ex`

**Tasks**:
1. Implement GenServer-based archive
2. Implement `add_to_archive/3`
3. Implement archive capacity management
4. Implement novelty-based replacement

**Tests**:
- Add to empty archive
- Add to full archive (replacement)
- Archive maintains most novel entries
- Concurrent access safety

**Deliverables**:
- [ ] NoveltyArchive GenServer
- [ ] Archive management logic
- [ ] Unit tests
- [ ] Concurrency tests
- [ ] Documentation

---

### Phase 5: Integration & Testing

#### Step 5.1: Optimizer Integration

**File**: `lib/jido_ai/runner/gepa/optimizer.ex` (extend existing)

**Tasks**:
1. Add diversity checking to evolution cycle
2. Add diversity intervention triggering
3. Add novelty-aware selection
4. Add adaptive mutation rate
5. Add novelty archive updates

**Tests**:
- Full evolution cycle with diversity enforcement
- Intervention triggering when diversity low
- Novelty scores affecting selection
- Mutation rate adaptation
- Archive growth over generations

**Deliverables**:
- [ ] Integrated optimizer
- [ ] Integration tests
- [ ] Documentation

---

#### Step 5.2: Configuration

**Tasks**:
1. Add `DiversityConfig` to optimizer config
2. Add sensible defaults
3. Add configuration validation

**Tests**:
- Default configuration works
- Custom configuration respected
- Invalid configuration rejected

**Deliverables**:
- [ ] Configuration integration
- [ ] Tests
- [ ] Documentation

---

#### Step 5.3: End-to-End Testing

**Tests**:
1. **Convergence Prevention Test**:
   - Start with low-diversity population
   - Verify diversity increases over generations
   - Verify no premature convergence

2. **Novelty Exploration Test**:
   - Run optimization with novelty rewards
   - Verify behavioral diversity increases
   - Verify novel approaches discovered

3. **Performance Test**:
   - Measure diversity overhead (<10% time increase)
   - Verify similarity matrix scaling
   - Benchmark archive operations

4. **Comparison Test**:
   - Run optimization WITH diversity enforcement
   - Run optimization WITHOUT diversity enforcement
   - Compare final solution quality and diversity

**Deliverables**:
- [ ] End-to-end tests
- [ ] Performance benchmarks
- [ ] Comparison studies
- [ ] Documentation

---

## Success Criteria

### Functional Requirements

- [ ] Similarity detection correctly identifies near-duplicates (>95% accuracy)
- [ ] Diversity metrics accurately reflect population heterogeneity
- [ ] Diversity promotion increases variation when triggered
- [ ] Novelty scoring rewards behaviorally unique prompts
- [ ] Integration doesn't break existing optimizer functionality

### Performance Requirements

- [ ] Similarity matrix construction: O(P²) with P = population size
- [ ] Text similarity comparison: <10ms per pair
- [ ] Diversity metrics calculation: <100ms for population of 50
- [ ] Novelty scoring: <50ms per candidate
- [ ] Total overhead: <15% of generation time

### Quality Requirements

- [ ] Prevents premature convergence (maintains diversity >0.3 throughout evolution)
- [ ] Balances exploration and exploitation (converges faster than random search)
- [ ] Produces behaviorally diverse high-quality prompts
- [ ] Scales to populations of 100+ candidates
- [ ] Configurable and tunable for different optimization scenarios

---

## Testing Strategy

### Unit Tests

**For each module**:
- Test all public functions
- Test edge cases (empty, nil, extreme values)
- Test error handling
- Test data structure validation

**Coverage target**: >90%

### Integration Tests

1. **SimilarityDetector + DiversityMetrics**:
   - Similarity matrix feeds into metrics calculation
   - Metrics correctly aggregate similarity data

2. **DiversityMetrics + DiversityPromoter**:
   - Low diversity triggers promotion
   - Promotion strategies increase diversity

3. **NoveltyScorer + NoveltyArchive**:
   - Scores based on archive comparison
   - Archive updates with novel candidates

4. **Full Pipeline**:
   - Similarity → Metrics → Promotion → Novelty
   - All components work together

### Property-Based Tests

Using StreamData:

```elixir
property "similarity is symmetric" do
  check all prompt_a <- prompt_generator(),
            prompt_b <- prompt_generator() do
    {:ok, result_ab} = SimilarityDetector.compare_prompts(prompt_a, prompt_b, :text)
    {:ok, result_ba} = SimilarityDetector.compare_prompts(prompt_b, prompt_a, :text)

    assert_in_delta result_ab.similarity_score, result_ba.similarity_score, 0.001
  end
end

property "diversity promotion increases diversity" do
  check all population <- homogeneous_population_generator(),
            metrics <- diversity_metrics_generator(:low) do
    {:ok, promoted_pop} = DiversityPromoter.promote_diversity(population, metrics, config)

    original_diversity = calculate_diversity(population)
    promoted_diversity = calculate_diversity(promoted_pop)

    assert promoted_diversity > original_diversity
  end
end

property "similarity scores are bounded [0, 1]" do
  check all prompt_a <- prompt_generator(),
            prompt_b <- prompt_generator() do
    {:ok, result} = SimilarityDetector.compare_prompts(prompt_a, prompt_b, :text)

    assert result.similarity_score >= 0.0
    assert result.similarity_score <= 1.0
  end
end
```

### Performance Tests

```elixir
defmodule Jido.AI.Runner.GEPA.Diversity.PerformanceTest do
  use ExUnit.Case

  @tag :performance
  test "similarity matrix scales quadratically" do
    sizes = [10, 20, 50, 100]

    times =
      for size <- sizes do
        population = generate_population(size)
        {time, _result} = :timer.tc(fn ->
          SimilarityDetector.detect_similarities(population, config)
        end)
        {size, time}
      end

    # Verify O(n²) scaling
    # Time ratio should be approximately (size² / prev_size²)
    # ...
  end

  @tag :performance
  test "diversity metrics fast enough for real-time use" do
    population = generate_population(50)
    {:ok, similarity_matrix} = SimilarityDetector.detect_similarities(population, config)

    {time, _result} = :timer.tc(fn ->
      DiversityMetrics.calculate_metrics(population, similarity_matrix, config)
    end)

    # Should be <100ms
    assert time < 100_000  # microseconds
  end
end
```

---

## Risks and Mitigations

### Risk 1: Computational Cost

**Risk**: Similarity detection is O(P²), may be slow for large populations.

**Mitigation**:
- Use cheap text similarity as primary metric
- Only use expensive semantic similarity for borderline cases
- Cache similarity results (prompts don't change within generation)
- Parallelize comparisons using Task.async_stream
- Limit population size (practical limit: 100 candidates)

### Risk 2: Balancing Diversity and Quality

**Risk**: Too much diversity enforcement may sacrifice fitness.

**Mitigation**:
- Use adaptive novelty weights based on diversity level
- Only intervene when diversity below threshold
- Prefer targeted diversification over random injection
- Monitor both fitness and diversity trends
- Make novelty weight configurable

### Risk 3: Defining "Behavioral" for Prompts

**Risk**: Hard to characterize prompt "behavior" without expensive evaluations.

**Mitigation**:
- Start with text and structural similarity (cheap)
- Use behavioral similarity only when trajectories available
- Reuse trajectory data from fitness evaluation (no extra cost)
- Allow configuration to disable expensive similarity strategies

### Risk 4: Archive Management Overhead

**Risk**: Novelty archive adds memory and computational overhead.

**Mitigation**:
- Limit archive size (default: 50 entries)
- Efficient nearest-neighbor search (use k-d tree or approximation)
- Lazy archive updates (only after generation, not per candidate)
- Make archive optional via configuration

### Risk 5: Integration Complexity

**Risk**: Adding diversity enforcement to existing optimizer may introduce bugs.

**Mitigation**:
- Extensive integration tests
- Feature flag to disable diversity enforcement
- Gradual rollout (disabled by default initially)
- Monitor diversity and fitness trends in parallel
- Comprehensive error handling

---

## Dependencies

### Internal

- `Jido.AI.Runner.GEPA.Population` - Population management
- `Jido.AI.Runner.GEPA.TrajectoryAnalyzer` - Behavioral analysis
- `Jido.AI.Runner.GEPA.Crossover.Segmenter` - Structural similarity
- `Jido.AI.Runner.GEPA.Mutation.Orchestrator` - Diversification mutations

### External

- Elixir stdlib (`String`, `Enum`, `MapSet`)
- `TypedStruct` - Data structure definitions
- (Optional) `Nx` for vector operations in semantic similarity
- (Optional) Embedding provider for semantic similarity

---

## Future Enhancements

### 1. Embedding-Based Semantic Similarity

**Current**: Text-based similarity (Levenshtein, Jaccard, n-grams)

**Enhancement**: Use sentence embeddings for true semantic similarity
- Integrate with embedding providers (OpenAI, Cohere, etc.)
- Cache embeddings (expensive to generate)
- Cosine similarity in embedding space
- Better capture semantic equivalence

**Effort**: Medium (requires embedding provider integration)

### 2. Advanced Clustering

**Current**: Simple threshold-based clustering

**Enhancement**: Sophisticated clustering algorithms
- DBSCAN for density-based clustering
- Hierarchical clustering with dendrograms
- Automatic cluster count detection
- Cluster quality metrics

**Effort**: Medium

### 3. Multi-Objective Diversity

**Current**: Single diversity metric

**Enhancement**: Pareto frontier of diversity objectives
- Text diversity
- Structural diversity
- Behavioral diversity
- Quality-diversity trade-off visualization

**Effort**: High (requires Stage 2: Pareto Management)

### 4. Learned Diversity Metrics

**Current**: Hand-crafted distance functions

**Enhancement**: Learn behavioral distance from data
- Train distance metric from successful/failed prompts
- Adaptive weighting of features
- Meta-learning across optimization runs

**Effort**: High (research-level)

### 5. Incremental Similarity Updates

**Current**: Rebuild entire similarity matrix each generation

**Enhancement**: Incrementally update matrix
- Only compute similarities for new candidates
- Reuse similarities for unchanged candidates
- Maintain similarity matrix across generations

**Effort**: Medium

---

## Documentation Requirements

### Module Documentation

Each module should have:
- Clear purpose statement
- Usage examples
- Parameter descriptions
- Return value documentation
- Complexity analysis
- Integration points

### Algorithm Documentation

Document key algorithms:
- Similarity calculation (all strategies)
- Diversity metrics (formulas and interpretations)
- Behavioral distance (feature weights and rationale)
- Novelty scoring (k-NN approach)

### Configuration Guide

Document all configuration options:
- `DiversityConfig` fields and defaults
- When to adjust thresholds
- Performance implications
- Recommended values for different scenarios

### Integration Guide

Document how to:
- Enable/disable diversity enforcement
- Configure similarity strategies
- Tune diversity thresholds
- Interpret diversity metrics
- Debug diversity issues

---

## Timeline Estimate

**Total**: ~4-5 weeks (160-200 hours)

### Week 1: Similarity Detection (Subtask 1.4.3.1)
- Day 1-2: Text similarity strategies (16h)
- Day 3: Structural similarity (8h)
- Day 4-5: SimilarityDetector core + testing (16h)

### Week 2: Diversity Metrics (Subtask 1.4.3.2)
- Day 1-2: Core metrics implementation (16h)
- Day 3: Assessment and reporting (8h)
- Day 4-5: Population integration + testing (16h)

### Week 3: Diversity-Promoting Mutation (Subtask 1.4.3.3)
- Day 1-2: Promotion strategies (16h)
- Day 3: Adaptive mutation rate (8h)
- Day 4-5: Testing and refinement (16h)

### Week 4: Novelty Rewards (Subtask 1.4.3.4)
- Day 1-2: Behavioral characterization (16h)
- Day 3: Novelty scoring (8h)
- Day 4-5: Novelty archive + testing (16h)

### Week 5: Integration & Polish
- Day 1-2: Optimizer integration (16h)
- Day 3: End-to-end testing (8h)
- Day 4-5: Documentation and polish (16h)

---

## Acceptance Criteria

### Implementation Complete When:

- [ ] All subtasks (1.4.3.1 - 1.4.3.4) implemented
- [ ] All modules have >90% test coverage
- [ ] All integration tests pass
- [ ] Performance benchmarks meet requirements
- [ ] Documentation complete
- [ ] Code reviewed and approved

### Functional Validation:

- [ ] Similarity detection identifies duplicates correctly
- [ ] Diversity metrics reflect population heterogeneity
- [ ] Low diversity triggers promotion
- [ ] Promotion increases diversity measurably
- [ ] Novelty scoring rewards unique behaviors
- [ ] Prevents premature convergence in test scenarios

### Quality Validation:

- [ ] No breaking changes to existing optimizer
- [ ] Configurable and tunable
- [ ] Efficient enough for production use
- [ ] Clear, comprehensive documentation
- [ ] All edge cases handled gracefully

---

## References

### Research Papers

1. **Dominated Novelty Search** (2024): Dynamic fitness transformations for Quality-Diversity
2. **Quality-Diversity Algorithms**: Comprehensive survey of diversity maintenance
3. **Genetic Programming Diversity**: Analysis of distance measures and fitness correlation
4. **Novelty Search**: Original papers on behavioral diversity and exploration

### Related GEPA Tasks

- **Task 1.3.4**: Feedback Aggregation (similarity detection for suggestions)
- **Task 1.4.1**: Targeted Mutation Operators (used for diversification)
- **Task 1.4.2**: Crossover Operators (Segmenter reused for structural similarity)
- **Task 1.4.4**: Mutation Rate Adaptation (integrates with diversity-based adaptation)
- **Stage 2**: Pareto Frontier Management (will use diversity metrics)

### Codebase References

- `/lib/jido_ai/runner/gepa/population.ex` - Population management
- `/lib/jido_ai/runner/gepa/trajectory_analyzer.ex` - Behavioral analysis
- `/lib/jido_ai/runner/gepa/crossover/segmenter.ex` - Prompt segmentation
- `/lib/jido_ai/runner/gepa/feedback_aggregation/deduplicator.ex` - Similarity detection examples
- `/test/support/gepa_test_helper.ex` - Test utilities

---

## Summary

This feature adds critical diversity enforcement mechanisms to GEPA, preventing premature convergence and ensuring the evolutionary search explores the solution space effectively. The implementation balances computational efficiency (primarily cheap text-based similarity) with accuracy (optional expensive semantic similarity), and integrates seamlessly with existing mutation and crossover operators.

The four-layer approach—similarity detection, diversity metrics, diversity promotion, and novelty rewards—provides comprehensive diversity maintenance while remaining configurable and efficient enough for production use.
