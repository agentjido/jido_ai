defmodule Jido.AI.Runner.TreeOfThoughts.TreeNode do
  @moduledoc """
  Tree node structure for Tree-of-Thoughts reasoning.

  Each node represents a thought in the reasoning tree, containing:
  - The thought content (reasoning step)
  - The state at this point in reasoning
  - Parent and children references
  - Evaluation scores
  - Metadata for pruning and search

  ## Structure

  ```
  Root (initial state)
    ├─ Thought 1 (approach A)
    │   ├─ Thought 1.1 (refine A)
    │   └─ Thought 1.2 (alternative A)
    ├─ Thought 2 (approach B)
    │   └─ Thought 2.1 (refine B)
    └─ Thought 3 (approach C)
  ```

  ## Examples

      # Create root node
      root = TreeNode.new("Initial problem: What is 2+2?", %{problem: "2+2"})

      # Create child thought
      child = TreeNode.new("Let me break this down: 2+2 = 4", %{answer: 4}, parent_id: root.id)

      # Evaluate node
      TreeNode.set_value(child, 0.95)
  """

  @type t :: %__MODULE__{
          id: String.t(),
          thought: String.t(),
          state: map(),
          parent_id: String.t() | nil,
          children_ids: list(String.t()),
          value: float() | nil,
          visits: non_neg_integer(),
          depth: non_neg_integer(),
          metadata: map()
        }

  defstruct [
    :id,
    :thought,
    :state,
    :parent_id,
    children_ids: [],
    value: nil,
    visits: 0,
    depth: 0,
    metadata: %{}
  ]

  @doc """
  Creates a new tree node.

  ## Parameters

  - `thought` - The thought/reasoning content
  - `state` - The state at this reasoning point
  - `opts` - Options:
    - `:parent_id` - Parent node ID
    - `:depth` - Node depth (auto-calculated if parent provided)
    - `:metadata` - Additional metadata

  ## Returns

  New TreeNode struct
  """
  @spec new(String.t(), map(), keyword()) :: t()
  def new(thought, state, opts \\ []) do
    parent_id = Keyword.get(opts, :parent_id)
    depth = Keyword.get(opts, :depth, if(parent_id, do: 1, else: 0))
    metadata = Keyword.get(opts, :metadata, %{})

    %__MODULE__{
      id: generate_id(),
      thought: thought,
      state: state,
      parent_id: parent_id,
      depth: depth,
      metadata: metadata
    }
  end

  @doc """
  Sets the value (evaluation score) for a node.

  ## Parameters

  - `node` - The node to update
  - `value` - Value score (0.0 to 1.0)

  ## Returns

  Updated node
  """
  @spec set_value(t(), float()) :: t()
  def set_value(node, value) when is_float(value) or is_integer(value) do
    %{node | value: value * 1.0}
  end

  @doc """
  Increments the visit count for a node.

  Used in search algorithms to track exploration.

  ## Parameters

  - `node` - The node to update

  ## Returns

  Updated node
  """
  @spec increment_visits(t()) :: t()
  def increment_visits(node) do
    %{node | visits: node.visits + 1}
  end

  @doc """
  Adds a child node ID to this node's children list.

  ## Parameters

  - `node` - The parent node
  - `child_id` - ID of the child node

  ## Returns

  Updated node
  """
  @spec add_child(t(), String.t()) :: t()
  def add_child(node, child_id) do
    %{node | children_ids: [child_id | node.children_ids]}
  end

  @doc """
  Checks if a node is a leaf (has no children).

  ## Parameters

  - `node` - The node to check

  ## Returns

  Boolean indicating if node is a leaf
  """
  @spec leaf?(t()) :: boolean()
  def leaf?(node) do
    Enum.empty?(node.children_ids)
  end

  @doc """
  Checks if a node is the root (has no parent).

  ## Parameters

  - `node` - The node to check

  ## Returns

  Boolean indicating if node is root
  """
  @spec root?(t()) :: boolean()
  def root?(node) do
    is_nil(node.parent_id)
  end

  @doc """
  Gets the UCT (Upper Confidence Bound for Trees) score for node selection.

  Used in MCTS-style search to balance exploration and exploitation.

  Formula: value + c * sqrt(ln(parent_visits) / node_visits)

  ## Parameters

  - `node` - The node to score
  - `parent_visits` - Number of visits to parent node
  - `opts` - Options:
    - `:exploration_constant` - Exploration parameter c (default: 1.4)

  ## Returns

  UCT score
  """
  @spec uct_score(t(), non_neg_integer(), keyword()) :: float()
  def uct_score(node, parent_visits, opts \\ []) do
    c = Keyword.get(opts, :exploration_constant, 1.4)

    if node.visits == 0 do
      # Unvisited nodes get infinite priority
      :infinity
    else
      value = node.value || 0.5
      exploration = c * :math.sqrt(:math.log(parent_visits) / node.visits)
      value + exploration
    end
  end

  # Private functions

  defp generate_id do
    "node_#{System.unique_integer([:positive, :monotonic])}"
  end
end
