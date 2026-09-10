defmodule Jido.AI.Reasoning.GraphOfThoughts.Strategy do
  @moduledoc """
  Deprecated inspection helpers over retained v3 request graphs.

  Select the method with `Jido.AI.Reasoning.GraphOfThoughts.method/0`.
  Core Agent routes, Flow and the shared Session replace old Strategy execution.
  This module owns no commands, process, model call or request state.
  """

  @deprecated "Use Jido.AI.Reasoning.GraphOfThoughts.get_nodes/1"
  defdelegate get_nodes(agent), to: Jido.AI.Reasoning.GraphOfThoughts

  @deprecated "Use Jido.AI.Reasoning.GraphOfThoughts.get_edges/1"
  defdelegate get_edges(agent), to: Jido.AI.Reasoning.GraphOfThoughts

  @deprecated "Use Jido.AI.Reasoning.GraphOfThoughts.get_result/1"
  defdelegate get_result(agent), to: Jido.AI.Reasoning.GraphOfThoughts

  @deprecated "Use Jido.AI.Reasoning.GraphOfThoughts.get_best_node/1"
  defdelegate get_best_node(agent), to: Jido.AI.Reasoning.GraphOfThoughts

  @deprecated "Use Jido.AI.Reasoning.GraphOfThoughts.get_solution_path/1"
  defdelegate get_solution_path(agent), to: Jido.AI.Reasoning.GraphOfThoughts
end
