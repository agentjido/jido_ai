defmodule Jido.AI.Runner.TreeOfThoughts.Tree do
  @moduledoc """
  Tree structure management for Tree-of-Thoughts reasoning.

  Manages a collection of TreeNode instances with efficient lookup,
  traversal, and manipulation operations.

  ## Operations

  - **Construction**: Build tree by adding nodes
  - **Traversal**: BFS, DFS, path extraction
  - **Pruning**: Remove low-value branches
  - **Search**: Find nodes by criteria

  ## Examples

      tree = Tree.new("What is 2+2?", %{problem: "2+2"})

      # Add thoughts
      {:ok, {tree, child1}} = Tree.add_child(tree, tree.root_id, "Approach: Add directly", %{})
      {:ok, {tree, child2}} = Tree.add_child(tree, tree.root_id, "Approach: Count fingers", %{})

      # Traverse
      nodes = Tree.bfs(tree)

      # Extract path to node
      path = Tree.get_path(tree, child1.id)
  """

  alias Jido.AI.Runner.TreeOfThoughts.TreeNode

  @type t :: %__MODULE__{
          root_id: String.t(),
          nodes: %{String.t() => TreeNode.t()},
          size: non_neg_integer(),
          max_depth: non_neg_integer()
        }

  defstruct [
    :root_id,
    nodes: %{},
    size: 0,
    max_depth: 0
  ]

  @doc """
  Creates a new tree with a root node.

  ## Parameters

  - `thought` - Root thought content
  - `state` - Initial state

  ## Returns

  New Tree struct
  """
  @spec new(String.t(), map()) :: t()
  def new(thought, state) do
    root = TreeNode.new(thought, state)

    %__MODULE__{
      root_id: root.id,
      nodes: %{root.id => root},
      size: 1,
      max_depth: 0
    }
  end

  @doc """
  Adds a child node to a parent node.

  ## Parameters

  - `tree` - The tree
  - `parent_id` - Parent node ID
  - `thought` - Child thought content
  - `state` - Child state
  - `opts` - Options passed to TreeNode.new

  ## Returns

  `{:ok, {updated_tree, child_node}}` or `{:error, {:parent_not_found, parent_id}}`
  """
  @spec add_child(t(), String.t(), String.t(), map(), keyword()) ::
          {:ok, {t(), TreeNode.t()}} | {:error, {:parent_not_found, String.t()}}
  def add_child(tree, parent_id, thought, state, opts \\ []) do
    case Map.fetch(tree.nodes, parent_id) do
      {:ok, parent} ->
        child =
          TreeNode.new(
            thought,
            state,
            Keyword.merge(opts,
              parent_id: parent_id,
              depth: parent.depth + 1
            )
          )

        # Update parent to include child
        updated_parent = TreeNode.add_child(parent, child.id)

        # Update tree
        updated_tree = %{
          tree
          | nodes: Map.put(tree.nodes, parent_id, updated_parent) |> Map.put(child.id, child),
            size: tree.size + 1,
            max_depth: max(tree.max_depth, child.depth)
        }

        {:ok, {updated_tree, child}}

      :error ->
        {:error, {:parent_not_found, parent_id}}
    end
  end

  @doc """
  Gets a node by ID.

  ## Parameters

  - `tree` - The tree
  - `node_id` - Node ID

  ## Returns

  `{:ok, node}` or `{:error, :not_found}`
  """
  @spec get_node(t(), String.t()) :: {:ok, TreeNode.t()} | {:error, :not_found}
  def get_node(tree, node_id) do
    case Map.fetch(tree.nodes, node_id) do
      {:ok, node} -> {:ok, node}
      :error -> {:error, :not_found}
    end
  end

  @doc """
  Updates a node in the tree.

  ## Parameters

  - `tree` - The tree
  - `node` - Updated node

  ## Returns

  Updated tree
  """
  @spec update_node(t(), TreeNode.t()) :: t()
  def update_node(tree, node) do
    %{tree | nodes: Map.put(tree.nodes, node.id, node)}
  end

  @doc """
  Gets all children of a node.

  ## Parameters

  - `tree` - The tree
  - `node_id` - Parent node ID

  ## Returns

  List of child nodes
  """
  @spec get_children(t(), String.t()) :: list(TreeNode.t())
  def get_children(tree, node_id) do
    case get_node(tree, node_id) do
      {:ok, node} ->
        node.children_ids
        |> Enum.map(fn child_id -> Map.get(tree.nodes, child_id) end)
        |> Enum.reject(&is_nil/1)

      {:error, _} ->
        []
    end
  end

  @doc """
  Gets the parent of a node.

  ## Parameters

  - `tree` - The tree
  - `node_id` - Child node ID

  ## Returns

  `{:ok, parent}` or `{:error, :no_parent}` if root
  """
  @spec get_parent(t(), String.t()) :: {:ok, TreeNode.t()} | {:error, :no_parent}
  def get_parent(tree, node_id) do
    case get_node(tree, node_id) do
      {:ok, node} ->
        if node.parent_id do
          get_node(tree, node.parent_id)
        else
          {:error, :no_parent}
        end

      error ->
        error
    end
  end

  @doc """
  Gets the path from root to a node.

  ## Parameters

  - `tree` - The tree
  - `node_id` - Target node ID

  ## Returns

  List of nodes from root to target (inclusive)
  """
  @spec get_path(t(), String.t()) :: list(TreeNode.t())
  def get_path(tree, node_id) do
    case get_node(tree, node_id) do
      {:ok, node} ->
        build_path(tree, node, [])

      {:error, _} ->
        []
    end
  end

  @doc """
  Performs breadth-first search traversal.

  ## Parameters

  - `tree` - The tree
  - `opts` - Options:
    - `:start_id` - Starting node ID (default: root)
    - `:max_depth` - Maximum depth to traverse

  ## Returns

  List of nodes in BFS order
  """
  @spec bfs(t(), keyword()) :: list(TreeNode.t())
  def bfs(tree, opts \\ []) do
    start_id = Keyword.get(opts, :start_id, tree.root_id)
    max_depth = Keyword.get(opts, :max_depth, :infinity)

    case get_node(tree, start_id) do
      {:ok, start_node} ->
        bfs_traverse(tree, [start_node], [], max_depth)

      {:error, _} ->
        []
    end
  end

  @doc """
  Performs depth-first search traversal.

  ## Parameters

  - `tree` - The tree
  - `opts` - Options:
    - `:start_id` - Starting node ID (default: root)
    - `:max_depth` - Maximum depth to traverse

  ## Returns

  List of nodes in DFS order
  """
  @spec dfs(t(), keyword()) :: list(TreeNode.t())
  def dfs(tree, opts \\ []) do
    start_id = Keyword.get(opts, :start_id, tree.root_id)
    max_depth = Keyword.get(opts, :max_depth, :infinity)

    case get_node(tree, start_id) do
      {:ok, start_node} ->
        dfs_traverse(tree, start_node, [], max_depth)

      {:error, _} ->
        []
    end
  end

  @doc """
  Gets all leaf nodes (nodes with no children).

  ## Parameters

  - `tree` - The tree

  ## Returns

  List of leaf nodes
  """
  @spec get_leaves(t()) :: list(TreeNode.t())
  def get_leaves(tree) do
    tree.nodes
    |> Map.values()
    |> Enum.filter(&TreeNode.leaf?/1)
  end

  @doc """
  Prunes branches with value below threshold.

  Removes nodes (and their subtrees) with evaluation scores
  below the threshold.

  ## Parameters

  - `tree` - The tree
  - `threshold` - Minimum value to keep (0.0-1.0)

  ## Returns

  Pruned tree
  """
  @spec prune_by_value(t(), float()) :: t()
  def prune_by_value(tree, threshold) do
    # Find nodes to remove (value < threshold)
    nodes_to_remove =
      tree.nodes
      |> Map.values()
      |> Enum.filter(fn node ->
        !TreeNode.root?(node) && node.value && node.value < threshold
      end)
      |> Enum.map(& &1.id)
      |> MapSet.new()

    # Remove nodes and their descendants
    remove_nodes(tree, nodes_to_remove)
  end

  @doc """
  Prunes branches to maintain beam width at each level.

  Keeps only the top k nodes at each depth level based on value.

  ## Parameters

  - `tree` - The tree
  - `beam_width` - Number of nodes to keep per level

  ## Returns

  Pruned tree
  """
  @spec prune_by_beam_width(t(), pos_integer()) :: t()
  def prune_by_beam_width(tree, beam_width) do
    # Group nodes by depth
    nodes_by_depth =
      tree.nodes
      |> Map.values()
      |> Enum.reject(&TreeNode.root?/1)
      |> Enum.group_by(& &1.depth)

    # For each depth, keep top k by value
    nodes_to_remove =
      nodes_by_depth
      |> Enum.flat_map(fn {_depth, nodes} ->
        # Sort by value (descending), take bottom nodes to remove
        nodes
        |> Enum.sort_by(&(&1.value || 0.0), :desc)
        |> Enum.drop(beam_width)
        |> Enum.map(& &1.id)
      end)
      |> MapSet.new()

    remove_nodes(tree, nodes_to_remove)
  end

  # Private functions

  defp build_path(_tree, node, path) when is_nil(node.parent_id) do
    [node | path]
  end

  defp build_path(tree, node, path) do
    case get_parent(tree, node.id) do
      {:ok, parent} -> build_path(tree, parent, [node | path])
      {:error, _} -> [node | path]
    end
  end

  defp bfs_traverse(_tree, [], visited, _max_depth), do: Enum.reverse(visited)

  defp bfs_traverse(tree, queue, visited, max_depth) do
    [current | rest] = queue

    if current.depth >= max_depth do
      bfs_traverse(tree, rest, [current | visited], max_depth)
    else
      children = get_children(tree, current.id)
      new_queue = rest ++ children
      bfs_traverse(tree, new_queue, [current | visited], max_depth)
    end
  end

  defp dfs_traverse(tree, node, visited, max_depth) do
    visited = [node | visited]

    if node.depth >= max_depth do
      visited
    else
      children = get_children(tree, node.id)

      Enum.reduce(children, visited, fn child, acc ->
        dfs_traverse(tree, child, acc, max_depth)
      end)
    end
  end

  defp remove_nodes(tree, node_ids) when map_size(node_ids) == 0, do: tree

  defp remove_nodes(tree, node_ids) do
    # Get all descendants of nodes to remove
    all_to_remove = expand_to_descendants(tree, node_ids)

    # Update parent nodes to remove child references
    tree = update_parent_references(tree, all_to_remove)

    # Remove nodes
    updated_nodes =
      Enum.reduce(all_to_remove, tree.nodes, fn node_id, nodes ->
        Map.delete(nodes, node_id)
      end)

    # Recalculate size and max depth
    %{
      tree
      | nodes: updated_nodes,
        size: map_size(updated_nodes),
        max_depth: calculate_max_depth(updated_nodes)
    }
  end

  defp expand_to_descendants(tree, node_ids) do
    node_ids
    |> Enum.reduce(node_ids, fn node_id, acc ->
      descendants = get_all_descendants(tree, node_id)
      MapSet.union(acc, MapSet.new(descendants))
    end)
  end

  defp get_all_descendants(tree, node_id) do
    case get_node(tree, node_id) do
      {:ok, node} ->
        direct_children = node.children_ids

        grandchildren =
          Enum.flat_map(direct_children, fn child_id ->
            get_all_descendants(tree, child_id)
          end)

        direct_children ++ grandchildren

      {:error, _} ->
        []
    end
  end

  defp update_parent_references(tree, nodes_to_remove) do
    # For each node being removed, update its parent to remove the child reference
    Enum.reduce(nodes_to_remove, tree, fn node_id, acc_tree ->
      case get_node(acc_tree, node_id) do
        {:ok, node} when not is_nil(node.parent_id) ->
          case get_parent(acc_tree, node_id) do
            {:ok, parent} ->
              updated_parent = %{
                parent
                | children_ids: Enum.reject(parent.children_ids, &(&1 == node_id))
              }

              update_node(acc_tree, updated_parent)

            {:error, _} ->
              acc_tree
          end

        _ ->
          acc_tree
      end
    end)
  end

  defp calculate_max_depth(nodes) do
    nodes
    |> Map.values()
    |> Enum.map(& &1.depth)
    |> Enum.max(fn -> 0 end)
  end
end
