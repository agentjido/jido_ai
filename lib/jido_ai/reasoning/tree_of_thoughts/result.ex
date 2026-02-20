defmodule Jido.AI.Reasoning.TreeOfThoughts.Result do
  @moduledoc """
  Canonical structured result contract for Tree-of-Thoughts executions.

  This module builds a stable result payload from machine state that is safe for
  SDK consumers and CLI projections.
  """

  alias Jido.AI.Reasoning.TreeOfThoughts.Machine

  @type candidate :: %{
          node_id: String.t(),
          content: String.t(),
          score: float() | nil,
          depth: non_neg_integer(),
          path_ids: [String.t()],
          path_text: [String.t()]
        }

  @type termination :: %{
          reason: atom() | nil,
          status: Machine.external_status() | String.t() | nil,
          depth_reached: non_neg_integer(),
          node_count: non_neg_integer(),
          duration_ms: non_neg_integer()
        }

  @type tree :: %{
          node_count: non_neg_integer(),
          frontier_size: non_neg_integer(),
          traversal_strategy: Machine.traversal_strategy() | atom(),
          max_depth: pos_integer(),
          branching_factor: pos_integer()
        }

  @type t :: %{
          best: candidate() | nil,
          candidates: [candidate()],
          termination: termination(),
          tree: tree(),
          usage: map(),
          diagnostics: map()
        }

  @doc """
  Builds a structured ToT result from machine state.
  """
  @spec build(Machine.t(), keyword()) :: t()
  def build(%Machine{} = machine, opts \\ []) do
    top_k = opts[:top_k] || machine.top_k || 3
    diagnostics = opts[:diagnostics] || %{}

    candidates =
      machine
      |> ranked_candidates()
      |> Enum.take(max(top_k, 1))

    %{
      best: List.first(candidates),
      candidates: candidates,
      termination: %{
        reason: machine.termination_reason,
        status: machine.status,
        depth_reached: max_depth_reached(machine),
        node_count: map_size(machine.nodes),
        duration_ms: duration_ms(machine)
      },
      tree: %{
        node_count: map_size(machine.nodes),
        frontier_size: length(machine.frontier),
        traversal_strategy: machine.traversal_strategy,
        max_depth: machine.max_depth,
        branching_factor: machine.branching_factor
      },
      usage: machine.usage,
      diagnostics: diagnostics
    }
  end

  @doc """
  Extracts the best answer string from a structured ToT result.
  """
  @spec best_answer(map() | nil) :: String.t() | nil
  def best_answer(%{best: %{content: content}}) when is_binary(content), do: content
  def best_answer(_), do: nil

  @doc """
  Returns ranked candidates from a structured ToT result.
  """
  @spec top_candidates(map() | nil, pos_integer()) :: [candidate()]
  def top_candidates(%{candidates: candidates}, limit)
      when is_list(candidates) and is_integer(limit) and limit > 0 do
    Enum.take(candidates, limit)
  end

  def top_candidates(%{candidates: candidates}, _limit) when is_list(candidates), do: candidates
  def top_candidates(_, _), do: []

  defp ranked_candidates(%Machine{} = machine) do
    machine
    |> Machine.find_leaves()
    |> Enum.sort_by(&candidate_sort_key/1)
    |> Enum.map(&leaf_to_candidate(machine, &1))
  end

  defp candidate_sort_key(leaf) do
    # Sort by descending score, then descending depth for stability.
    {-(leaf.score || 0.0), -(leaf.depth || 0), leaf.id}
  end

  defp leaf_to_candidate(machine, leaf) do
    path = Machine.get_path_to_node(machine, leaf.id)

    %{
      node_id: leaf.id,
      content: leaf.content,
      score: leaf.score,
      depth: leaf.depth || 0,
      path_ids: Enum.map(path, & &1.id),
      path_text: Enum.map(path, & &1.content)
    }
  end

  defp max_depth_reached(%Machine{} = machine) do
    machine.nodes
    |> Map.values()
    |> Enum.map(&(&1.depth || 0))
    |> Enum.max(fn -> 0 end)
  end

  defp duration_ms(%Machine{started_at: nil}), do: 0
  defp duration_ms(%Machine{started_at: started_at}), do: System.monotonic_time(:millisecond) - started_at
end
