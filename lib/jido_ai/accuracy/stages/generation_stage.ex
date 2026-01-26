defmodule Jido.AI.Accuracy.Stages.GenerationStage do
  @moduledoc """
  Pipeline stage for multi-candidate generation.

  This stage generates multiple candidates using self-consistency
  with adaptive N based on query difficulty. The number of candidates
  is adjusted according to the difficulty level.

  ## Configuration

  - `:min_candidates` - Minimum candidates to generate (default: 3)
  - `:max_candidates` - Maximum candidates (default: 10)
  - `:batch_size` - Candidates per consensus check (default: 3)
  - `:early_stop_threshold` - Consensus for early stopping (default: 0.8)
  - `:generator` - Generator function (required)

  ## Output State

  Adds to the pipeline state:
  - `:candidates` - List of generated candidates
  - `:num_candidates` - Number of candidates generated
  - `:best_candidate` - The best candidate from aggregation

  ## Usage

      stage = GenerationStage.new(%{
        generator: fn query -> MyApp.generate(query) end
      })

  """

  @behaviour Jido.AI.Accuracy.PipelineStage

  alias Jido.AI.Accuracy.{
    AdaptiveSelfConsistency,
    Candidate
  }

  @type t :: %__MODULE__{
          min_candidates: pos_integer(),
          max_candidates: pos_integer(),
          batch_size: pos_integer(),
          early_stop_threshold: float(),
          generator: function() | nil
        }

  defstruct [
    :generator,
    min_candidates: 3,
    max_candidates: 10,
    batch_size: 3,
    early_stop_threshold: 0.8
  ]

  @impl true
  def name, do: :generation

  @impl true
  def required?, do: true

  @impl true
  def execute(input, config) do
    query = Map.get(input, :query)
    generator = Map.get(config, :generator) || Map.get(input, :generator)

    if is_binary(query) and query != "" do
      if is_function(generator) do
        # Ensure generator is in config for generate_candidates
        config_with_generator = Map.put(config, :generator, generator)
        generate_candidates(query, input, config_with_generator)
      else
        {:error, :generator_required}
      end
    else
      {:error, :invalid_query}
    end
  end

  @doc """
  Creates a new stage configuration.

  """
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      generator: Map.get(attrs, :generator),
      min_candidates: Map.get(attrs, :min_candidates, 3),
      max_candidates: Map.get(attrs, :max_candidates, 10),
      batch_size: Map.get(attrs, :batch_size, 3),
      early_stop_threshold: Map.get(attrs, :early_stop_threshold, 0.8)
    }
  end

  # Private functions

  defp generate_candidates(query, input, config) do
    # Get difficulty for adaptive N
    difficulty_estimate = Map.get(input, :difficulty)
    context = Map.get(input, :context, %{})

    # Build adaptive self-consistency config
    adapter = build_adapter(config)

    # Run adaptive self-consistency
    opts = [
      generator: wrap_generator(config, context),
      context: context
    ]

    opts =
      if difficulty_estimate do
        Keyword.put(opts, :difficulty_estimate, difficulty_estimate)
      else
        opts
      end

    case AdaptiveSelfConsistency.run(adapter, query, opts) do
      {:ok, best_candidate, metadata} ->
        # Extract all candidates from metadata if available
        candidates = Map.get(metadata, :candidates, [best_candidate])

        updated_state =
          input
          |> Map.put(:candidates, candidates)
          |> Map.put(:num_candidates, length(candidates))
          |> Map.put(:best_candidate, best_candidate)
          |> Map.put(:generation_metadata, metadata)

        {:ok, updated_state,
         %{
           num_candidates: length(candidates),
           actual_n: Map.get(metadata, :actual_n, length(candidates)),
           early_stopped: Map.get(metadata, :early_stopped, false),
           consensus: Map.get(metadata, :consensus)
         }}

      {:error, reason} ->
        {:error, {:generation_failed, reason}}
    end
  end

  defp build_adapter(config) do
    AdaptiveSelfConsistency.new!(%{
      min_candidates: Map.get(config, :min_candidates, 3),
      max_candidates: Map.get(config, :max_candidates, 10),
      batch_size: Map.get(config, :batch_size, 3),
      early_stop_threshold: Map.get(config, :early_stop_threshold, 0.8)
    })
  end

  defp wrap_generator(config, rag_context) do
    user_generator = Map.get(config, :generator)

    fn query ->
      user_generator
      |> call_generator(query, rag_context)
      |> normalize_generator_result()
    end
  end

  defp call_generator(gen, query, context) when is_function(gen, 2), do: gen.(query, context)
  defp call_generator(gen, query, _context) when is_function(gen, 1), do: gen.(query)
  defp call_generator(_, _, _), do: {:error, :invalid_generator_arity}

  defp normalize_generator_result({:ok, %Candidate{} = candidate}), do: {:ok, candidate}

  defp normalize_generator_result({:ok, content}) when is_binary(content),
    do: {:ok, Candidate.new!(%{content: content})}

  defp normalize_generator_result(%Candidate{} = candidate), do: {:ok, candidate}
  defp normalize_generator_result(content) when is_binary(content), do: {:ok, Candidate.new!(%{content: content})}
  defp normalize_generator_result({:error, _} = error), do: error
  defp normalize_generator_result(_), do: {:error, :invalid_generator_response}
end
