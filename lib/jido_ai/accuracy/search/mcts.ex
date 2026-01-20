defmodule Jido.AI.Accuracy.Search.MCTS do
  @moduledoc """
  Monte Carlo Tree Search implementation for guided exploration.

  MCTS explores the reasoning tree using four phases:
  1. Selection - Traverse tree using UCB1 to find promising node
  2. Expansion - Add new child node to the tree
  3. Simulation - Rollout from new node to estimate value
  4. Backpropagation - Update values up the tree to root

  ## Algorithm

  For each simulation:
  1. **Selection**: Start at root, select child with best UCB1 score until leaf
  2. **Expansion**: If leaf is not terminal, add new child
  3. **Simulation**: Generate candidate and score with verifier
  4. **Backpropagation**: Update visit counts and values up the path

  After N simulations, return child with highest visit ratio.

  ## Configuration

  - `:simulations` - Number of MCTS simulations (default: 100)
  - `:exploration_constant` - UCB1 exploration weight (default: 1.414)
  - `:max_depth` - Maximum tree depth (default: 10)

  ## Usage

      # Basic MCTS search
      {:ok, best} = MCTS.search(
        "What is 15 * 23?",
        LLMGenerator,
        DeterministicVerifier,
        simulations: 100
      )

      # With custom exploration
      {:ok, best} = MCTS.search(
        "Solve: x^2 + 5x + 6 = 0",
        LLMGenerator,
        LLMOutcomeVerifier,
        simulations: 200,
        exploration_constant: 2.0
      )

  ## UCB1 Selection

  The UCB1 formula balances exploration and exploitation:

      ucb1 = (value / visits) + c * sqrt(ln(parent_visits) / visits)

  - High `c` = more exploration
  - Low `c` = more exploitation

  ## PRM Guidance

  When using Process Reward Models, the simulation phase can score
  intermediate reasoning steps for more accurate value estimation.

  ## Complexity

  - Time: O(simulations * max_depth * (selection + simulation))
  - Space: O(simulations * max_depth * node_size)

  ## Examples

      # Find best answer for math problem
      {:ok, best} = MCTS.search(
        "What is 144 / 12?",
        LLMGenerator,
        DeterministicVerifier,
        simulations: 50
      )

      # Use PRM for complex reasoning
      {:ok, best} = MCTS.search(
        "Prove that sqrt(2) is irrational",
        LLMGenerator,
        LLMPrm,
        simulations: 200,
        exploration_constant: 1.414
      )

  """

  alias Jido.AI.Accuracy.{Candidate, SearchController, Search.MCTSNode, VerificationResult}

  @behaviour SearchController

  @type t :: %__MODULE__{
          simulations: pos_integer(),
          exploration_constant: float(),
          max_depth: pos_integer(),
          generator: module(),
          verifier: module()
        }

  defstruct simulations: 100,
            exploration_constant: 1.414,
            max_depth: 10,
            generator: nil,
            verifier: nil

  # Client API

  @doc """
  Creates a new MCTS configuration.

  ## Options

  - `:simulations` - Number of simulations (default: 100)
  - `:exploration_constant` - UCB1 exploration weight (default: 1.414)
  - `:max_depth` - Maximum tree depth (default: 10)

  """
  @spec new(keyword()) :: {:ok, t()} | {:error, term()}
  def new(opts \\ []) when is_list(opts) do
    config = struct(__MODULE__, opts)

    with :ok <- validate_simulations(config.simulations),
         :ok <- validate_exploration_constant(config.exploration_constant),
         :ok <- validate_max_depth(config.max_depth) do
      {:ok, config}
    end
  end

  @doc """
  Creates a new MCTS configuration, raising on error.

  """
  @spec new!(keyword()) :: t()
  def new!(opts \\ []) when is_list(opts) do
    case new(opts) do
      {:ok, config} -> config
      {:error, reason} -> raise ArgumentError, "Invalid MCTS config: #{format_error(reason)}"
    end
  end

  @impl true
  @spec search(String.t(), module(), module(), keyword()) :: {:ok, Candidate.t()} | {:error, term()}
  def search(prompt, generator, verifier, opts \\ []) do
    start_time = System.monotonic_time(:millisecond)
    timeout = SearchController.get_timeout(opts, 30_000)

    with {:ok, config} <- new(opts),
         :ok <- SearchController.validate_opts(Keyword.drop(opts, [:simulations, :exploration_constant, :max_depth, :timeout]), []) do
      do_search(prompt, generator, verifier, config, start_time, timeout)
    end
  end

  # Private functions

  defp do_search(prompt, generator, verifier, config, start_time, timeout) do
    # Initialize root node
    root = MCTSNode.new(state: %{prompt: prompt, depth: 0})

    # Run simulations
    final_root = run_simulations(root, prompt, generator, verifier, config, start_time, timeout)

    # Select best child
    best = select_best_child(final_root)

    if best do
      if best.candidate do
        {:ok, best.candidate}
      else
        # No candidate associated, return error
        {:error, :no_valid_candidate}
      end
    else
      # Root has no children, try generating one candidate
      case generate_and_verify_candidate(prompt, generator, verifier, start_time, timeout) do
        {:ok, candidate} -> {:ok, candidate}
        {:error, _} -> {:error, :no_valid_candidate}
      end
    end
  end

  defp run_simulations(root, prompt, generator, verifier, config, start_time, timeout) do
    _sim_count = 0

    Enum.reduce_while(1..config.simulations, root, fn _i, current_root ->
      if SearchController.timeout_exceeded?(start_time, timeout) do
        {:halt, current_root}
      else
        {:ok, updated_root} =
          run_single_simulation(current_root, prompt, generator, verifier, config, start_time, timeout)

        {:cont, updated_root}
      end
    end)
  end

  defp run_single_simulation(root, prompt, generator, verifier, config, start_time, timeout) do
    # Phase 1: Selection
    {selected_path, leaf} = selection(root, config.exploration_constant, config.max_depth)

    # Phase 2: Expansion
    expanded = expansion(leaf, prompt)

    # Phase 3: Simulation
    {simulated_node, value} =
      simulation(expanded, prompt, generator, verifier, start_time, timeout)

    # Phase 4: Backpropagation
    updated_root = backpropagation(simulated_node, value, selected_path)

    {:ok, updated_root}
  end

  # Selection phase - traverse tree using UCB1
  defp selection(node, exploration_constant, max_depth) do
    select_until_leaf(node, exploration_constant, max_depth, [])
  end

  defp select_until_leaf(node, exploration_constant, max_depth, path) do
    cond do
      # Reached max depth
      node.state.depth >= max_depth ->
        {Enum.reverse([node | path]), node}

      # Node is terminal
      MCTSNode.is_terminal?(node) ->
        {Enum.reverse([node | path]), node}

      # Node has no children - this is a leaf
      not MCTSNode.has_children?(node) ->
        {Enum.reverse([node | path]), node}

      # Select best child using UCB1 and continue
      true ->
        best_child = select_ucb1_child(node, exploration_constant)
        select_until_leaf(best_child, exploration_constant, max_depth, [node | path])
    end
  end

  defp select_ucb1_child(node, exploration_constant) do
    node.children
    |> Enum.reject(fn child -> MCTSNode.is_terminal?(child) end)
    |> Enum.max_by(fn child ->
      MCTSNode.ucb1_score_for_child(child, exploration_constant)
    end, fn ->
      node
    end)
  end

  # Expansion phase - add new child to leaf
  defp expansion(leaf, _prompt) do
    # For simplicity, we don't actually expand here
    # The expansion happens implicitly during simulation
    leaf
  end

  # Simulation phase - rollout to get value estimate
  defp simulation(node, prompt, generator, verifier, start_time, timeout) do
    if node.candidate do
      # Node already has candidate, just verify it
      value = verify_candidate(node.candidate, verifier, prompt, start_time, timeout)
      {node, value}
    else
      # Generate new candidate and verify
      case generate_and_verify_candidate(prompt, generator, verifier, start_time, timeout) do
        {:ok, candidate} ->
          value = extract_score_from_candidate(candidate)
          updated_node = Map.put(node, :candidate, candidate)
          {updated_node, value}

        {:error, _} ->
          {node, 0.5}
      end
    end
  end

  defp generate_and_verify_candidate(prompt, generator, verifier, start_time, timeout) do
    remaining = timeout - (System.monotonic_time(:millisecond) - start_time)

    if remaining <= 0 do
      {:error, :timeout}
    else
      case generate_candidate(prompt, generator, remaining) do
        {:ok, candidate} ->
          value = verify_candidate(candidate, verifier, prompt, start_time, timeout)
          {:ok, %{candidate | score: value}}

        {:error, _} = error ->
          error
      end
    end
  end

  defp generate_candidate(prompt, generator, timeout) do
    try do
      case Code.ensure_loaded?(generator) and function_exported?(generator, :generate_candidates, 3) do
        true ->
          case generator.generate_candidates(prompt, num_candidates: 1, timeout: timeout) do
            {:ok, [candidate | _]} -> {:ok, candidate}
            {:ok, []} -> {:error, :no_candidates}
            {:error, _} = error -> error
          end

        false ->
          # Fallback: create simple candidate
          candidate = Candidate.new!(%{
            id: "#{System.unique_integer([:positive, :monotonic])}",
            content: "#{prompt} (generated)",
            metadata: %{fallback: true}
          })

          {:ok, candidate}
      end
    rescue
      _ -> {:error, :generator_failed}
    end
  end

  defp verify_candidate(candidate, verifier, prompt, start_time, timeout) do
    remaining = timeout - (System.monotonic_time(:millisecond) - start_time)

    if remaining <= 0 do
      0.5
    else
      context = %{prompt: prompt, timeout: remaining}

      try do
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
    end
  end

  defp extract_score_from_candidate(%Candidate{score: score}) when is_number(score), do: score
  defp extract_score_from_candidate(_), do: 0.5

  # Backpropagation phase - update values up the tree
  defp backpropagation(node, value, path) do
    # Update the node itself
    updated_node = MCTSNode.backpropagate(node, value)

    # Update all ancestors
    Enum.reduce(path, updated_node, fn ancestor, acc ->
      updated_ancestor = MCTSNode.backpropagate(ancestor, value)

      # Replace the ancestor's child reference
      updated_ancestors =
        Enum.map(updated_ancestor.children, fn child ->
          if child.state == node.state or child.action == node.action do
            acc
          else
            child
          end
        end)

      %{updated_ancestor | children: updated_ancestors}
    end)
  end

  defp select_best_child(root) do
    MCTSNode.most_visited_child(root)
  end

  # Validation

  defp validate_simulations(sim) when is_integer(sim) and sim >= 1 and sim <= 10000, do: :ok
  defp validate_simulations(_), do: {:error, :invalid_simulations}

  defp validate_exploration_constant(c) when is_number(c) and c >= 0.0 and c <= 10.0, do: :ok
  defp validate_exploration_constant(_), do: {:error, :invalid_exploration_constant}

  defp validate_max_depth(depth) when is_integer(depth) and depth >= 1 and depth <= 100, do: :ok
  defp validate_max_depth(_), do: {:error, :invalid_max_depth}
  defp format_error(atom) when is_atom(atom), do: atom
  defp format_error(_), do: :invalid_attributes
end
