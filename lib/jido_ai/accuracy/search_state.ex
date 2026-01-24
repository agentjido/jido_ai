defmodule Jido.AI.Accuracy.SearchState do
  @moduledoc """
  State tracking for search algorithms.

  SearchState tracks the progress of a search algorithm, including
  current candidates, best result, and remaining budget.

  ## Fields

  - `:nodes` - Current search nodes/candidates being explored
  - `:best_node` - Best node/candidate found so far
  - `:iterations` - Number of iterations performed
  - `:budget_remaining` - Compute budget remaining (e.g., simulations, expansions)
  - `:converged` - Whether search has converged
  - `:metadata` - Additional state metadata
  - `:start_time` - Search start time for timeout checking
  - `:stagnation_count` - Iterations since best score improved

  ## Usage

      # Initialize new search state
      state = SearchState.new!(%{
        nodes: [],
        budget_remaining: 100
      })

      # Update best node when found
      state = SearchState.update_best(state, better_candidate)

      # Check if search should stop
      if SearchState.should_stop?(state) do
        # Return best result
      end

  ## Convergence Criteria

  Search is considered converged when:
  1. Budget is exhausted (`budget_remaining <= 0`)
  2. Max iterations reached (via metadata)
  3. Stagnation: best score hasn't improved in N iterations

  """

  alias Jido.AI.Accuracy.Candidate

  @type search_node :: %{candidate: Candidate.t(), score: float(), metadata: map()}

  @type t :: %__MODULE__{
          nodes: [search_node()],
          best_node: search_node() | nil,
          iterations: non_neg_integer(),
          budget_remaining: integer(),
          converged: boolean(),
          metadata: map(),
          start_time: integer(),
          stagnation_count: non_neg_integer()
        }

  @enforce_keys [:budget_remaining]

  defstruct nodes: [],
            best_node: nil,
            iterations: 0,
            budget_remaining: 100,
            converged: false,
            metadata: %{},
            start_time: System.monotonic_time(:millisecond),
            stagnation_count: 0

  # Client API

  @doc """
  Creates a new search state from the given attributes.

  ## Options

  - `:nodes` - Initial nodes/candidates (default: `[]`)
  - `:best_node` - Initial best node (default: `nil`)
  - `:iterations` - Initial iteration count (default: `0`)
  - `:budget_remaining` - Compute budget (required)
  - `:converged` - Converged flag (default: `false`)
  - `:metadata` - Additional metadata (default: `%{}`)
  - `:stagnation_count` - Stagnation counter (default: `0`)

  ## Returns

  - `{:ok, state}` - Valid state created
  - `{:error, reason}` - Validation failed

  ## Examples

      iex> {:ok, state} = SearchState.new(%{budget_remaining: 100})
      iex> state.budget_remaining
      100

      iex> {:ok, state} = SearchState.new(%{
      ...>   budget_remaining: 50,
      ...>   metadata: %{max_iterations: 10}
      ...> })

  """
  @spec new(keyword()) :: {:ok, t()} | {:error, term()}
  def new(opts) when is_list(opts) do
    # Check for required budget_remaining key
    case Keyword.fetch(opts, :budget_remaining) do
      :error ->
        {:error, :missing_budget_remaining}

      {:ok, _budget} ->
        state = struct(__MODULE__, opts)

        with :ok <- validate_budget(state.budget_remaining),
             :ok <- validate_iterations(state.iterations) do
          {:ok, %{state | start_time: System.monotonic_time(:millisecond)}}
        end
    end
  end

  @doc """
  Creates a new search state, raising on error.

  ## Examples

      iex> SearchState.new!(%{budget_remaining: 100})
      %SearchState{budget_remaining: 100}

  """
  @spec new!(keyword()) :: t()
  def new!(opts) when is_list(opts) do
    case new(opts) do
      {:ok, state} -> state
      {:error, reason} -> raise ArgumentError, "Invalid SearchState: #{format_error(reason)}"
    end
  end

  @doc """
  Updates the best node if the new candidate has a higher score.

  ## Parameters

  - `state` - Current search state
  - `candidate` - New candidate to consider
  - `score` - Score for the candidate
  - `metadata` - Optional metadata for the node

  ## Returns

  - Updated state with new best node (if score is higher)
  - Original state (if score is not higher)

  ## Examples

      iex> state = SearchState.new!(%{budget_remaining: 100})
      iex> state = SearchState.update_best(state, candidate, 0.9)
      iex> state.best_node.score
      0.9

  """
  @spec update_best(t(), Candidate.t(), float(), map()) :: t()
  def update_best(%__MODULE__{} = state, %Candidate{} = candidate, score, metadata \\ %{}) do
    new_node = %{candidate: candidate, score: score, metadata: metadata}

    current_best_score = get_best_score(state)

    if score > current_best_score do
      %{state | best_node: new_node, stagnation_count: 0}
    else
      # Increment stagnation counter
      %{state | stagnation_count: state.stagnation_count + 1}
    end
  end

  @doc """
  Updates the best node directly from a node struct.

  ## Examples

      iex> node = %{candidate: candidate, score: 0.9, metadata: %{}}
      iex> state = SearchState.update_best_node(state, node)

  """
  @spec update_best_node(t(), search_node()) :: t()
  def update_best_node(%__MODULE__{} = state, %{score: _score} = node) do
    current_best_score = get_best_score(state)

    if node.score > current_best_score do
      %{state | best_node: node, stagnation_count: 0}
    else
      %{state | stagnation_count: state.stagnation_count + 1}
    end
  end

  @doc """
  Checks if search should stop.

  Returns `true` if any of:
  - Budget exhausted
  - Converged flag is true
  - Max iterations reached (from metadata)

  ## Examples

      iex> state = SearchState.new!(%{budget_remaining: 0})
      iex> SearchState.should_stop?(state)
      true

  """
  @spec should_stop?(t()) :: boolean()
  def should_stop?(%__MODULE__{} = state) do
    budget_exhausted?(state) or state.converged or max_iterations_reached?(state)
  end

  @doc """
  Checks if budget is exhausted.

  """
  @spec budget_exhausted?(t()) :: boolean()
  def budget_exhausted?(%__MODULE__{budget_remaining: budget}) do
    budget <= 0
  end

  @doc """
  Checks if max iterations reached (from metadata).

  """
  @spec max_iterations_reached?(t()) :: boolean()
  def max_iterations_reached?(%__MODULE__{iterations: iterations, metadata: metadata}) do
    case Map.get(metadata, :max_iterations) do
      nil -> false
      max when is_integer(max) -> iterations >= max
      _ -> false
    end
  end

  @doc """
  Checks if search has stagnated (no improvement in N iterations).

  """
  @spec stagnated?(t(), pos_integer()) :: boolean()
  def stagnated?(%__MODULE__{stagnation_count: count}, threshold) when is_integer(threshold) do
    count >= threshold
  end

  @doc """
  Adds a node to the state.

  ## Examples

      iex> state = SearchState.new!(%{budget_remaining: 100})
      iex> node = %{candidate: candidate, score: 0.8, metadata: %{}}
      iex> state = SearchState.add_node(state, node)
      iex> length(state.nodes)
      1

  """
  @spec add_node(t(), search_node()) :: t()
  def add_node(%__MODULE__{} = state, %{candidate: %Candidate{}} = node) do
    %{state | nodes: [node | state.nodes]}
  end

  @doc """
  Adds multiple nodes to the state.

  """
  @spec add_nodes(t(), [search_node()]) :: t()
  def add_nodes(%__MODULE__{} = state, nodes) when is_list(nodes) do
    %{state | nodes: nodes ++ state.nodes}
  end

  @doc """
  Sets the nodes in the state.

  """
  @spec set_nodes(t(), [search_node()]) :: t()
  def set_nodes(%__MODULE__{} = state, nodes) when is_list(nodes) do
    %{state | nodes: nodes}
  end

  @doc """
  Decrements the budget by the specified amount.

  ## Examples

      iex> state = SearchState.new!(%{budget_remaining: 100})
      iex> state = SearchState.decrement_budget(state, 10)
      iex> state.budget_remaining
      90

  """
  @spec decrement_budget(t(), pos_integer()) :: t()
  def decrement_budget(%__MODULE__{} = state, amount) when is_integer(amount) and amount > 0 do
    %{state | budget_remaining: max(0, state.budget_remaining - amount)}
  end

  @doc """
  Increments the iteration counter.

  """
  @spec increment_iteration(t()) :: t()
  def increment_iteration(%__MODULE__{} = state) do
    %{state | iterations: state.iterations + 1}
  end

  @doc """
  Marks the search as converged.

  """
  @spec converge(t()) :: t()
  def converge(%__MODULE__{} = state) do
    %{state | converged: true}
  end

  @doc """
  Gets the best candidate from the state.

  Returns `nil` if no best node exists.

  """
  @spec get_best_candidate(t()) :: Candidate.t() | nil
  def get_best_candidate(%__MODULE__{best_node: nil}), do: nil
  def get_best_candidate(%__MODULE__{best_node: %{candidate: candidate}}), do: candidate

  @doc """
  Gets the best score from the state.

  Returns `0.0` if no best node exists.

  """
  @spec get_best_score(t()) :: float()
  def get_best_score(%__MODULE__{best_node: nil}), do: 0.0
  def get_best_score(%__MODULE__{best_node: %{score: score}}), do: score

  @doc """
  Gets the elapsed time since search started.

  """
  @spec elapsed_ms(t()) :: pos_integer()
  def elapsed_ms(%__MODULE__{start_time: start_time}) do
    System.monotonic_time(:millisecond) - start_time
  end

  @doc """
  Puts a value in the metadata map.

  """
  @spec put_metadata(t(), atom(), term()) :: t()
  def put_metadata(%__MODULE__{} = state, key, value) do
    %{state | metadata: Map.put(state.metadata, key, value)}
  end

  @doc """
  Gets a value from the metadata map.

  """
  @spec get_metadata(t(), atom(), term()) :: term()
  def get_metadata(%__MODULE__{metadata: metadata}, key, default \\ nil) do
    Map.get(metadata, key, default)
  end

  # Private functions

  defp validate_budget(budget) when is_integer(budget) and budget >= 0, do: :ok
  defp validate_budget(_), do: {:error, :invalid_budget}

  defp validate_iterations(iterations) when is_integer(iterations) and iterations >= 0, do: :ok
  defp validate_iterations(_), do: {:error, :invalid_iterations}
  defp format_error(atom) when is_atom(atom), do: atom
end
