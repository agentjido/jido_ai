defmodule Jido.AI.Accuracy.Search.MCTSNode do
  @moduledoc """
  Node structure for Monte Carlo Tree Search.

  Each node represents a state in the search tree with visit counts,
  accumulated values, and child nodes.

  ## Fields

  - `:state` - The reasoning state at this node
  - `:visits` - Number of times this node was visited
  - `:value` - Cumulative value from this node
  - `:children` - Child nodes
  - `:parent` - Parent node reference
  - `:is_terminal` - Whether this is a terminal node
  - `:candidate` - Associated candidate if terminal
  - `:action` - Action leading to this node

  ## UCB1 Formula

  The UCB1 score balances exploration and exploitation:

      ucb1 = (value / visits) + c * sqrt(ln(parent_visits) / visits)

  Where `c` is the exploration constant (typically 1.414 for sqrt(2)).

  ## Usage

      # Create root node
      root = MCTSNode.new!(state: "initial")

      # Add child
      child = MCTSNode.add_child(root, %{state: "child_state"})

      # Update value after simulation
      updated = MCTSNode.update_value(child, 0.8)

      # Calculate UCB1 score
      score = MCTSNode.ucb1_score(child, 1.414)

  """

  alias Jido.AI.Accuracy.Candidate

  @type t :: %__MODULE__{
          state: term(),
          visits: pos_integer(),
          value: float(),
          children: [t()],
          parent: t() | nil,
          is_terminal: boolean(),
          candidate: Candidate.t() | nil,
          action: term()
        }

  defstruct state: nil,
            visits: 0,
            value: 0.0,
            children: [],
            parent: nil,
            is_terminal: false,
            candidate: nil,
            action: nil

  # Client API

  @doc """
  Creates a new MCTS node from the given attributes.

  ## Options

  - `:state` - The reasoning state at this node (default: `nil`)
  - `:visits` - Visit count (default: `0`)
  - `:value` - Cumulative value (default: `0.0`)
  - `:children` - Child nodes (default: `[]`)
  - `:parent` - Parent node (default: `nil`)
  - `:is_terminal` - Terminal flag (default: `false`)
  - `:candidate` - Associated candidate (default: `nil`)
  - `:action` - Action leading to this node (default: `nil`)

  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    struct(__MODULE__, opts)
  end

  @doc """
  Creates a new MCTS node, raising on error.

  """
  @spec new!(keyword()) :: t()
  def new!(opts \\ []) do
    new(opts)
  end

  @doc """
  Calculates the UCB1 score for this node.

  The UCB1 (Upper Confidence Bound 1) formula balances exploration
  and exploitation in MCTS.

  ## Parameters

  - `node` - The node to calculate score for
  - `exploration_constant` - The `c` parameter (default: 1.414 for sqrt(2))

  ## Returns

  - The UCB1 score, or `:infinity` for unvisited nodes

  ## Examples

      # Unvisited node returns infinity
      iex> MCTSNode.ucb1_score(%MCTSNode{visits: 0, parent_visits: 10})
      :infinity

      # Visited node returns finite score
      iex> MCTSNode.ucb1_score(%MCTSNode{visits: 5, value: 3.0, parent_visits: 20}, 1.414)
      0.6 + 1.414 * sqrt(ln(20) / 5)

  """
  @spec ucb1_score(t(), float()) :: float() | :infinity
  def ucb1_score(%__MODULE__{visits: visits}, _exploration_constant) when is_integer(visits) and visits == 0 do
    :infinity
  end

  def ucb1_score(%__MODULE__{visits: visits, value: value}, exploration_constant)
      when is_integer(visits) and visits > 0 do
    exploitation = value / visits
    exploration = exploration_constant * :math.sqrt(1 / visits)
    exploitation + exploration
  end

  @doc """
  Calculates the UCB1 score for a child node.

  Takes into account the parent's visit count for exploration term.

  ## Parameters

  - `node` - The child node
  - `exploration_constant` - The `c` parameter (default: 1.414)

  """
  @spec ucb1_score_for_child(t(), float()) :: float() | :infinity
  def ucb1_score_for_child(%__MODULE__{visits: 0}, _exploration_constant), do: :infinity

  def ucb1_score_for_child(%__MODULE__{} = node, exploration_constant) do
    parent_visits = if node.parent, do: node.parent.visits, else: 1

    exploitation = node.value / node.visits
    exploration = exploration_constant * :math.sqrt(:math.log(parent_visits) / node.visits)

    exploitation + exploration
  end

  @doc """
  Adds a child node to this node.

  Sets the parent reference on the child.

  """
  @spec add_child(t(), t() | keyword()) :: t()
  def add_child(%__MODULE__{} = parent, child_opts) when is_list(child_opts) do
    child = new(child_opts)
    add_child(parent, child)
  end

  def add_child(%__MODULE__{} = parent, %__MODULE__{} = child) do
    child_with_parent = %{child | parent: parent}
    %{parent | children: [child_with_parent | parent.children]}
  end

  @doc """
  Updates the node's value with a new simulation result.

  The value is accumulated: `new_value = old_value + result`.

  """
  @spec update_value(t(), float()) :: t()
  def update_value(%__MODULE__{} = node, result) when is_number(result) do
    %{node | value: node.value + result}
  end

  @doc """
  Increments the visit count for this node.

  """
  @spec increment_visits(t()) :: t()
  def increment_visits(%__MODULE__{} = node) do
    %{node | visits: node.visits + 1}
  end

  @doc """
  Updates the node after a simulation (both visits and value).

  """
  @spec backpropagate(t(), float()) :: t()
  def backpropagate(%__MODULE__{} = node, result) when is_number(result) do
    node
    |> increment_visits()
    |> update_value(result)
  end

  @doc """
  Checks if this node is fully expanded (all children created).

  For a node to be fully expanded, it should have children available
  to explore. This is typically context-dependent and should be
  overridden based on the problem domain.

  """
  @spec is_fully_expanded?(t()) :: boolean()
  def is_fully_expanded?(%__MODULE__{children: []}), do: false
  def is_fully_expanded?(%__MODULE__{children: children}), do: not Enum.empty?(children)

  @doc """
  Checks if this node is a terminal node (no further expansion possible).

  """
  @spec is_terminal?(t()) :: boolean()
  def is_terminal?(%__MODULE__{is_terminal: terminal}), do: terminal

  @doc """
  Marks this node as terminal.

  """
  @spec mark_terminal(t()) :: t()
  def mark_terminal(%__MODULE__{} = node) do
    %{node | is_terminal: true}
  end

  @doc """
  Gets the best child according to visit count ratio.

  Selects the child with the highest `value / visits` ratio.

  """
  @spec best_child(t(), keyword()) :: t() | nil
  def best_child(%__MODULE__{children: []}, _opts), do: nil

  def best_child(%__MODULE__{children: children}, opts) when is_list(children) do
    temperature = Keyword.get(opts, :temperature, 0.0)

    if temperature > 0 do
      # Temperature sampling: add randomness proportional to temperature
      child_with_temperature_sampling(children, temperature)
    else
      # Select child with highest value/visits ratio
      Enum.max_by(children, fn child ->
        if child.visits > 0 do
          child.value / child.visits
        else
          0.0
        end
      end)
    end
  end

  @doc """
  Gets the most visited child.

  """
  @spec most_visited_child(t()) :: t() | nil
  def most_visited_child(%__MODULE__{children: []}), do: nil

  def most_visited_child(%__MODULE__{children: children}) do
    Enum.max_by(children, fn child -> child.visits end, fn -> nil end)
  end

  @doc """
  Gets the average value for this node.

  """
  @spec average_value(t()) :: float()
  def average_value(%__MODULE__{visits: 0}), do: 0.0
  def average_value(%__MODULE__{visits: visits, value: value}), do: value / visits

  @doc """
  Finds a child node by action.

  """
  @spec find_child_by_action(t(), term()) :: t() | nil
  def find_child_by_action(%__MODULE__{children: children}, action) do
    Enum.find(children, fn child -> child.action == action end)
  end

  @doc """
  Gets the number of children.

  """
  @spec child_count(t()) :: non_neg_integer()
  def child_count(%__MODULE__{children: children}), do: length(children)

  @doc """
  Checks if this node has any children.

  """
  @spec has_children?(t()) :: boolean()
  def has_children?(%__MODULE__{children: []}), do: false
  def has_children?(%__MODULE__{children: children}) when is_list(children), do: not Enum.empty?(children)

  @doc """
  Gets the depth of this node from the root.

  """
  @spec depth(t()) :: non_neg_integer()
  def depth(%__MODULE__{parent: nil}), do: 0
  def depth(%__MODULE__{parent: parent}), do: 1 + depth(parent)

  # Private functions

  defp child_with_temperature_sampling(children, temperature) do
    # Calculate weights based on visit count and temperature
    weights =
      Enum.map(children, fn child ->
        if child.visits > 0 do
          :math.exp(child.value / child.visits / temperature)
        else
          1.0
        end
      end)

    total = Enum.sum(weights)

    # Normalize and sample
    normalized = Enum.map(weights, fn w -> w / total end)
    r = :rand.uniform()

    select_child_by_cumulative_probability(children, normalized, r, 0.0)
  end

  defp select_child_by_cumulative_probability([child | _rest], [prob | _], r, _acc) when r <= prob do
    child
  end

  defp select_child_by_cumulative_probability([child | rest], [prob | probs], r, acc) do
    if r <= acc + prob do
      child
    else
      select_child_by_cumulative_probability(rest, probs, r, acc + prob)
    end
  end

  defp select_child_by_cumulative_probability([], _, _, _), do: nil
end
