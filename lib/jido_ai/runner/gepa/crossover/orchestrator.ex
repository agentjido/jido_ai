defmodule JidoAI.Runner.GEPA.Crossover.Orchestrator do
  @moduledoc """
  Main orchestrator for crossover operations.

  This module coordinates the entire crossover pipeline:
  1. Segment parent prompts
  2. Check compatibility
  3. Select crossover strategy
  4. Perform crossover (exchange or blend)
  5. Validate offspring
  6. Return results

  ## Usage

      # Basic crossover
      {:ok, result} = Orchestrator.perform_crossover(prompt_a, prompt_b)
      result.offspring_prompts  # => ["offspring1", "offspring2"]

      # With configuration
      config = %CrossoverConfig{strategy: :uniform, allow_blending: true}
      {:ok, result} = Orchestrator.perform_crossover(prompt_a, prompt_b, config)

  ## Examples

      iex> {:ok, result} = Orchestrator.perform_crossover(prompt_a, prompt_b)
      iex> length(result.offspring_prompts)
      2
      iex> result.validated
      true
  """

  alias JidoAI.Runner.GEPA.Crossover.{
    Blender,
    CompatibilityChecker,
    CrossoverConfig,
    CrossoverResult,
    Exchanger,
    Segmenter
  }

  @doc """
  Performs crossover on two parent prompts.

  ## Parameters

  - `prompt_a` - First parent prompt (string)
  - `prompt_b` - Second parent prompt (string)
  - `config` - CrossoverConfig struct (optional)

  ## Returns

  - `{:ok, CrossoverResult.t()}` - Successful crossover with offspring
  - `{:error, reason}` - If crossover fails

  ## Examples

      {:ok, result} = Orchestrator.perform_crossover(
        "Solve this step by step",
        "Show your work clearly",
        %CrossoverConfig{strategy: :semantic}
      )
  """
  @spec perform_crossover(String.t(), String.t(), CrossoverConfig.t() | nil) ::
          {:ok, CrossoverResult.t()} | {:error, term()}
  def perform_crossover(prompt_a, prompt_b, config \\ nil)

  def perform_crossover(prompt_a, prompt_b, config)
      when is_binary(prompt_a) and is_binary(prompt_b) do
    config = config || %CrossoverConfig{}

    with {:ok, segmented_a} <- Segmenter.segment(prompt_a),
         {:ok, segmented_b} <- Segmenter.segment(prompt_b),
         {:ok, compatibility} <-
           CompatibilityChecker.check_compatibility(segmented_a, segmented_b),
         {:ok, strategy} <- select_strategy(compatibility, config),
         {:ok, offspring} <- execute_crossover(segmented_a, segmented_b, strategy, config),
         {:ok, validated_offspring} <- maybe_validate(offspring, config) do
      result =
        build_result(
          [prompt_a, prompt_b],
          validated_offspring,
          strategy,
          segmented_a,
          segmented_b,
          config
        )

      {:ok, result}
    else
      {:error, :incompatible_prompts} ->
        {:error, :parents_incompatible}

      error ->
        error
    end
  end

  def perform_crossover(_prompt_a, _prompt_b, _config) do
    {:error, :invalid_prompts}
  end

  @doc """
  Performs crossover on already-segmented prompts.

  Useful when you've already performed segmentation and want to skip that step.

  ## Parameters

  - `segmented_a` - First segmented prompt
  - `segmented_b` - Second segmented prompt
  - `config` - CrossoverConfig struct (optional)

  ## Returns

  - `{:ok, CrossoverResult.t()}` - Successful crossover
  - `{:error, reason}` - If crossover fails
  """
  @spec perform_crossover_segmented(map(), map(), CrossoverConfig.t() | nil) ::
          {:ok, CrossoverResult.t()} | {:error, term()}
  def perform_crossover_segmented(segmented_a, segmented_b, config \\ nil) do
    config = config || %CrossoverConfig{}

    with {:ok, compatibility} <-
           CompatibilityChecker.check_compatibility(segmented_a, segmented_b),
         {:ok, strategy} <- select_strategy(compatibility, config),
         {:ok, offspring} <- execute_crossover(segmented_a, segmented_b, strategy, config),
         {:ok, validated_offspring} <- maybe_validate(offspring, config) do
      result =
        build_result(
          [segmented_a.raw_text, segmented_b.raw_text],
          validated_offspring,
          strategy,
          segmented_a,
          segmented_b,
          config
        )

      {:ok, result}
    end
  end

  @doc """
  Performs batch crossover on multiple prompt pairs.

  ## Parameters

  - `prompt_pairs` - List of {prompt_a, prompt_b} tuples
  - `config` - CrossoverConfig struct (optional)

  ## Returns

  - `{:ok, results}` - List of CrossoverResult structs
  - `{:error, reason}` - If batch processing fails

  ## Examples

      pairs = [
        {"prompt1a", "prompt1b"},
        {"prompt2a", "prompt2b"}
      ]
      {:ok, results} = Orchestrator.batch_crossover(pairs)
      length(results)  # => 2
  """
  @spec batch_crossover(list({String.t(), String.t()}), CrossoverConfig.t() | nil) ::
          {:ok, list(CrossoverResult.t())} | {:error, term()}
  def batch_crossover(prompt_pairs, config \\ nil) when is_list(prompt_pairs) do
    results =
      Enum.map(prompt_pairs, fn {prompt_a, prompt_b} ->
        perform_crossover(prompt_a, prompt_b, config)
      end)

    # Check if any failed
    errors = Enum.filter(results, &match?({:error, _}, &1))

    if Enum.empty?(errors) do
      successful = Enum.map(results, fn {:ok, result} -> result end)
      {:ok, successful}
    else
      {:error, {:batch_failures, errors}}
    end
  end

  # Private functions

  defp select_strategy(compatibility, config) do
    cond do
      # User specified strategy
      config.strategy != :semantic ->
        {:ok, config.strategy}

      # Not compatible enough for crossover
      not compatibility.compatible ->
        {:error, :incompatible_prompts}

      # Use recommended strategy
      compatibility.recommended_strategy != nil ->
        {:ok, compatibility.recommended_strategy}

      # Default to semantic
      true ->
        {:ok, :semantic}
    end
  end

  defp execute_crossover(segmented_a, segmented_b, strategy, config) do
    case strategy do
      :single_point ->
        execute_single_point(segmented_a, segmented_b, config)

      :two_point ->
        execute_two_point(segmented_a, segmented_b, config)

      :uniform ->
        execute_uniform(segmented_a, segmented_b, config)

      :semantic ->
        # Semantic strategy uses blending
        execute_blending(segmented_a, segmented_b, config)

      _ ->
        {:error, {:unknown_strategy, strategy}}
    end
  end

  defp execute_single_point(segmented_a, segmented_b, _config) do
    case Exchanger.single_point(segmented_a, segmented_b) do
      {:ok, {offspring1, offspring2}} ->
        {:ok, [offspring1, offspring2]}

      error ->
        error
    end
  end

  defp execute_two_point(segmented_a, segmented_b, _config) do
    case Exchanger.two_point(segmented_a, segmented_b) do
      {:ok, {offspring1, offspring2}} ->
        {:ok, [offspring1, offspring2]}

      error ->
        error
    end
  end

  defp execute_uniform(segmented_a, segmented_b, _config) do
    case Exchanger.uniform(segmented_a, segmented_b) do
      {:ok, {offspring1, offspring2}} ->
        {:ok, [offspring1, offspring2]}

      error ->
        error
    end
  end

  defp execute_blending(segmented_a, segmented_b, config) do
    if config.allow_blending do
      case Blender.blend_prompts(segmented_a, segmented_b) do
        {:ok, blended} ->
          {:ok, [blended]}

        error ->
          error
      end
    else
      # Fall back to uniform crossover if blending disabled
      execute_uniform(segmented_a, segmented_b, config)
    end
  end

  defp maybe_validate(offspring, config) do
    if config.validate_offspring do
      validate_offspring(offspring)
    else
      {:ok, offspring}
    end
  end

  defp validate_offspring(offspring) do
    # Basic validation: non-empty, reasonable length
    invalid =
      Enum.filter(offspring, fn prompt ->
        byte_size(prompt) < 10 or byte_size(prompt) > 50_000
      end)

    if Enum.empty?(invalid) do
      {:ok, offspring}
    else
      {:error, :invalid_offspring}
    end
  end

  defp build_result(parent_prompts, offspring, strategy, segmented_a, segmented_b, _config) do
    %CrossoverResult{
      id: Uniq.UUID.uuid4(),
      parent_ids: [segmented_a.prompt_id, segmented_b.prompt_id],
      offspring_prompts: offspring,
      strategy_used: strategy,
      segments_exchanged: extract_exchanged_segments(segmented_a, segmented_b, strategy),
      segments_blended: extract_blended_segments(segmented_a, segmented_b, strategy),
      validated: true,
      validation_score: calculate_validation_score(offspring),
      metadata: %{
        parent_a_structure: segmented_a.structure_type,
        parent_b_structure: segmented_b.structure_type,
        parent_prompts: parent_prompts,
        offspring_count: length(offspring)
      }
    }
  end

  defp extract_exchanged_segments(segmented_a, segmented_b, strategy)
       when strategy in [:single_point, :two_point, :uniform] do
    # For exchange strategies, return segments from both parents
    segmented_a.segments ++ segmented_b.segments
  end

  defp extract_exchanged_segments(_segmented_a, _segmented_b, _strategy), do: []

  defp extract_blended_segments(segmented_a, segmented_b, :semantic) do
    # For blending, return segments that were blended
    segmented_a.segments ++ segmented_b.segments
  end

  defp extract_blended_segments(_segmented_a, _segmented_b, _strategy), do: []

  defp calculate_validation_score(offspring) do
    # Simple score based on offspring characteristics
    avg_length = Enum.sum(Enum.map(offspring, &byte_size/1)) / length(offspring)

    cond do
      avg_length < 50 -> 0.3
      avg_length < 200 -> 0.6
      avg_length < 1000 -> 0.8
      true -> 0.9
    end
  end
end
