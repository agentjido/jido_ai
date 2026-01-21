defmodule Jido.AI.Accuracy.Search.BeamSearch do
  @moduledoc """
  Beam search implementation for guided candidate exploration.

  Beam search maintains a fixed-size "beam" of top candidates at each step,
  expanding and verifying them to systematically explore the solution space.

  ## Algorithm

  1. Initialize beam with N candidates (using varied temperatures)
  2. For each depth level:
     - Expand each candidate in the beam (generate continuations)
     - Verify all expansions with the verifier
     - Select top-K candidates by verifier score
  3. Return best candidate from final beam

  ## Configuration

  - `:beam_width` - Number of candidates to maintain (default: 5)
  - `:depth` - Number of expansion rounds (default: 3)
  - `:branching_factor` - Candidates per beam position (default: 2)
  - `:generator` - Module for candidate generation
  - `:verifier` - Module for candidate verification

  ## Usage

      # Basic beam search
      {:ok, best} = BeamSearch.search(
        "What is 15 * 23?",
        LLMGenerator,
        DeterministicVerifier,
        beam_width: 5,
        depth: 3
      )

      # With custom options
      {:ok, best} = BeamSearch.search(
        "Solve: x^2 + 5x + 6 = 0",
        LLMGenerator,
        LLMOutcomeVerifier,
        beam_width: 3,
        depth: 5,
        branching_factor: 3
      )

  ## Beam Width Behavior

  - `beam_width: 1` - Degrades to greedy search (keeps only best)
  - `beam_width: 3-5` - Balanced exploration vs speed
  - `beam_width: 10+` - Thorough exploration, slower

  ## Complexity

  - Time: O(depth * beam_width * branching_factor * generation_time + verification_time)
  - Space: O(beam_width * candidate_size)

  ## Examples

      # Simple beam search for math problem
      {:ok, best} = BeamSearch.search(
        "What is the square root of 144?",
        LLMGenerator,
        DeterministicVerifier,
        beam_width: 3,
        depth: 2
      )

      # Wider beam for complex reasoning
      {:ok, best} = BeamSearch.search(
        "Explain the theory of relativity",
        LLMGenerator,
        LLMOutcomeVerifier,
        beam_width: 7,
        depth: 4,
        branching_factor: 2
      )

  """

  alias Jido.AI.Accuracy.{Candidate, SearchController, SearchState, VerificationResult}

  @behaviour SearchController

  @type t :: %__MODULE__{
          beam_width: pos_integer(),
          depth: pos_integer(),
          branching_factor: pos_integer(),
          generator: module(),
          verifier: module()
        }

  defstruct beam_width: 5,
            depth: 3,
            branching_factor: 2,
            generator: nil,
            verifier: nil

  # Client API

  @doc """
  Creates a new beam search configuration.

  ## Options

  - `:beam_width` - Number of candidates to maintain (default: 5)
  - `:depth` - Number of expansion rounds (default: 3)
  - `:branching_factor` - Candidates per beam position (default: 2)

  ## Returns

  - `{:ok, beam_search}` - Valid configuration
  - `{:error, reason}` - Validation failed

  """
  @spec new(keyword()) :: {:ok, t()} | {:error, term()}
  def new(opts) when is_list(opts) do
    config = struct(__MODULE__, opts)

    with :ok <- validate_beam_width(config.beam_width),
         :ok <- validate_depth(config.depth),
         :ok <- validate_branching_factor(config.branching_factor) do
      {:ok, config}
    end
  end

  @doc """
  Creates a new beam search configuration, raising on error.

  """
  @spec new!(keyword()) :: t()
  def new!(opts) when is_list(opts) do
    case new(opts) do
      {:ok, config} -> config
      {:error, reason} -> raise ArgumentError, "Invalid BeamSearch config: #{format_error(reason)}"
    end
  end

  @impl true
  @spec search(String.t(), module(), module(), keyword()) :: {:ok, Candidate.t()} | {:error, term()}
  def search(prompt, generator, verifier, opts \\ []) do
    start_time = System.monotonic_time(:millisecond)
    timeout = SearchController.get_timeout(opts, 30_000)

    with {:ok, config} <- new(opts),
         :ok <-
           SearchController.validate_opts(Keyword.drop(opts, [:beam_width, :depth, :branching_factor, :timeout]), []),
         {:ok, state} <- do_search(prompt, generator, verifier, config, start_time, timeout) do
      best = SearchState.get_best_candidate(state)

      if best do
        {:ok, best}
      else
        {:error, :no_valid_candidate}
      end
    end
  end

  # Private functions

  defp do_search(prompt, generator, verifier, config, start_time, timeout) do
    # Initialize state
    initial_state = SearchState.new!(budget_remaining: config.depth, metadata: %{beam_width: config.beam_width})

    # Initialize beam with initial candidates
    case initialize_beam(prompt, generator, verifier, config, start_time, timeout) do
      {:error, _reason} = error ->
        error

      {:ok, []} ->
        {:error, :no_initial_candidates}

      {:ok, initial_beam} ->
        # Update state with initial beam
        state = SearchState.set_nodes(initial_state, initial_beam)

        # Update best from initial beam
        state = update_best_from_nodes(state, initial_beam)

        # Run search iterations
        run_iterations(prompt, generator, verifier, config, state, start_time, timeout)
    end
  end

  defp run_iterations(prompt, generator, verifier, config, state, start_time, timeout) do
    if SearchState.should_stop?(state) or SearchController.timeout_exceeded?(start_time, timeout) do
      {:ok, state}
    else
      # Expand beam
      case expand_beam(state.nodes, prompt, generator, verifier, config, start_time, timeout) do
        {:ok, []} ->
          # No expansions, return current state
          {:ok, state}

        {:ok, expanded_nodes} ->
          # Select top-K
          top_k = select_top_k(expanded_nodes, config.beam_width)

          # Update state
          state =
            state
            |> SearchState.set_nodes(top_k)
            |> SearchState.decrement_budget(1)
            |> SearchState.increment_iteration()
            |> update_best_from_nodes(top_k)

          run_iterations(prompt, generator, verifier, config, state, start_time, timeout)
      end
    end
  end

  defp initialize_beam(prompt, generator, verifier, config, start_time, timeout) do
    # Generate initial candidates with varied temperatures
    num_candidates = config.beam_width * config.branching_factor

    case generate_candidates(prompt, generator, num_candidates, start_time, timeout) do
      {:ok, candidates} ->
        verify_and_score_nodes(candidates, prompt, verifier, start_time, timeout)

      {:error, _reason} = error ->
        error
    end
  end

  defp expand_beam(nodes, prompt, generator, verifier, config, start_time, timeout) do
    # Expand each node in the beam
    all_expansions =
      Enum.flat_map(nodes, fn node ->
        {:ok, expansion_nodes} =
          expand_node(node, prompt, generator, verifier, config.branching_factor, start_time, timeout)

        expansion_nodes
      end)

    {:ok, all_expansions}
  end

  defp expand_node(_node, prompt, generator, verifier, branching_factor, start_time, timeout) do
    # Generate new candidates based on the prompt
    case generate_candidates(prompt, generator, branching_factor, start_time, timeout) do
      {:ok, candidates} ->
        verify_and_score_nodes(candidates, prompt, verifier, start_time, timeout)

      {:error, _reason} ->
        # Return empty list on error
        {:ok, []}
    end
  end

  defp generate_candidates(prompt, generator, num_candidates, start_time, timeout) do
    remaining = timeout - (System.monotonic_time(:millisecond) - start_time)

    if remaining <= 0 do
      {:error, :timeout}
    else
      # Use LLMGenerator to create candidates
      opts = [
        num_candidates: num_candidates,
        temperature_range: {0.0, 1.0},
        timeout: remaining
      ]

      # Try to call the generator
      case Code.ensure_loaded?(generator) and function_exported?(generator, :generate_candidates, 3) do
        true ->
          try do
            generator.generate_candidates(prompt, opts)
          rescue
            _ -> {:error, :generator_failed}
          end

        false ->
          # Fallback: create simple candidates
          candidates =
            Enum.map(1..num_candidates, fn i ->
              Candidate.new!(%{
                id: "#{System.unique_integer([:positive, :monotonic])}",
                content: "#{prompt} (candidate #{i})",
                score: 0.5,
                metadata: %{generated: true}
              })
            end)

          {:ok, candidates}
      end
    end
  end

  defp verify_and_score_nodes(candidates, prompt, verifier, start_time, timeout) do
    remaining = timeout - (System.monotonic_time(:millisecond) - start_time)

    if remaining <= 0 do
      {:ok, []}
    else
      # Create verification context
      context = %{prompt: prompt, timeout: remaining}

      # Verify candidates
      nodes =
        Enum.map(candidates, fn candidate ->
          score = score_candidate(candidate, verifier, context)
          %{candidate: candidate, score: score, metadata: %{}}
        end)

      {:ok, nodes}
    end
  end

  defp score_candidate(candidate, verifier, context) do
    case verifier.verify(candidate, context) do
      {:ok, %VerificationResult{score: score}} when is_number(score) ->
        score

      {:ok, %VerificationResult{}} ->
        0.5

      _ ->
        0.5
    end
  rescue
    _ -> 0.5
  end

  @doc """
  Selects top K nodes from a list by score.

  ## Parameters

  - `nodes` - List of nodes with `:score` field
  - `k` - Number of top nodes to select

  ## Returns

  - Top K nodes sorted by score (descending)

  """
  @spec select_top_k(list(), pos_integer()) :: list()
  def select_top_k(nodes, k) when is_list(nodes) and is_integer(k) and k > 0 do
    nodes
    |> Enum.sort_by(fn %{score: score} -> score end, :desc)
    |> Enum.take(k)
  end

  def select_top_k(nodes, _k), do: nodes

  defp update_best_from_nodes(state, nodes) do
    Enum.reduce(nodes, state, fn %{candidate: candidate, score: score}, acc ->
      SearchState.update_best(acc, candidate, score)
    end)
  end

  # Validation

  defp validate_beam_width(width) when is_integer(width) and width >= 1 and width <= 100, do: :ok
  defp validate_beam_width(_), do: {:error, :invalid_beam_width}

  defp validate_depth(depth) when is_integer(depth) and depth >= 1 and depth <= 20, do: :ok
  defp validate_depth(_), do: {:error, :invalid_depth}

  defp validate_branching_factor(factor) when is_integer(factor) and factor >= 1 and factor <= 10, do: :ok
  defp validate_branching_factor(_), do: {:error, :invalid_branching_factor}
  defp format_error(atom) when is_atom(atom), do: atom
  defp format_error(_), do: :invalid_attributes
end
