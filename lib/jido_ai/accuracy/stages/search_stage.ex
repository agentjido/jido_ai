defmodule Jido.AI.Accuracy.Stages.SearchStage do
  @moduledoc """
  Pipeline stage for search-based candidate selection.

  This is an optional stage that runs beam search or MCTS to find
  a better candidate through search-based exploration.

  ## Configuration

  - `:enabled` - Whether search is enabled (default: true)
  - `:algorithm` - Search algorithm (:beam_search or :mcts)
  - `:beam_width` - Beam width for beam search (default: 5)
  - `:iterations` - Number of search iterations (default: 50)
  - `:timeout` - Maximum search time in ms (default: 10_000)

  ## Output State

  Updates the pipeline state:
  - `:best_candidate` - Updates with search-improved candidate
  - `:search_applied` - Whether search was applied

  ## Usage

      stage = SearchStage.new(%{
        algorithm: :beam_search,
        beam_width: 5
      })

  """

  @behaviour Jido.AI.Accuracy.PipelineStage

  alias Jido.AI.Accuracy.PipelineStage

  @type t :: %__MODULE__{
          enabled: boolean(),
          algorithm: :beam_search | :mcts,
          beam_width: pos_integer(),
          iterations: pos_integer(),
          timeout: pos_integer()
        }

  defstruct enabled: true,
            algorithm: :beam_search,
            beam_width: 5,
            iterations: 50,
            timeout: 10_000

  @impl PipelineStage
  def name, do: :search

  @impl PipelineStage
  def required?, do: false

  @impl PipelineStage
  def execute(input, config) do
    enabled = Map.get(config, :enabled, true)
    candidates = Map.get(input, :candidates)

    cond do
      !enabled ->
        # Stage disabled, skip
        {:ok, Map.put(input, :search_applied, false), %{skipped: true}}

      is_list(candidates) and candidates != [] ->
        run_search(candidates, input, config)

      # No candidates to search
      true ->
        {:ok, Map.put(input, :search_applied, false), %{no_candidates: true}}
    end
  end

  @doc """
  Creates a new stage configuration.

  """
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      enabled: Map.get(attrs, :enabled, true),
      algorithm: Map.get(attrs, :algorithm, :beam_search),
      beam_width: Map.get(attrs, :beam_width, 5),
      iterations: Map.get(attrs, :iterations, 50),
      timeout: Map.get(attrs, :timeout, 10_000)
    }
  end

  # Private functions

  defp run_search(candidates, input, config) do
    algorithm = Map.get(config, :algorithm, :beam_search)
    query = Map.get(input, :query)
    context = Map.get(input, :context, %{})

    # Try to run search with the configured algorithm
    case do_search(algorithm, candidates, query, context, config) do
      {:ok, best_candidate} ->
        updated_state =
          input
          |> Map.put(:best_candidate, best_candidate)
          |> Map.put(:search_applied, true)

        {:ok, updated_state, %{algorithm: algorithm, improved: true}}

      {:error, :search_not_available} ->
        # Search module not available, skip without error
        {:ok, Map.put(input, :search_applied, false), %{search_not_available: true}}

      {:error, reason} ->
        # Search failed, but continue with original best candidate
        {:ok, Map.put(input, :search_applied, false), %{search_failed: reason}}
    end
  end

  defp do_search(:beam_search, _candidates, _query, _context, _config) do
    # Beam search requires a generator module to create new candidates.
    # In the pipeline context, we already have generated candidates,
    # so beam search isn't directly applicable here.
    # For now, skip beam search and return the candidates as-is.
    {:error, :search_not_available}
  end

  defp do_search(:mcts, candidates, query, context, config) do
    case get_mcts_module() do
      {:ok, module} ->
        iterations = Map.get(config, :iterations, 50)

        if function_exported?(module, :search, 4) do
          module.search(module, candidates, query, %{
            iterations: iterations,
            context: context
          })
        else
          {:error, :search_not_available}
        end

      {:error, _} ->
        {:error, :search_not_available}
    end
  end

  defp do_search(_algorithm, _candidates, _query, _context, _config) do
    {:error, :search_not_available}
  end

  # Try to get MCTS module if available
  defp get_mcts_module do
    module = Module.safe_concat([Jido, AI, Accuracy, Search, MCTS])

    if Code.ensure_loaded?(module) do
      {:ok, module}
    else
      {:error, :not_found}
    end
  rescue
    _ -> {:error, :not_found}
  end
end
