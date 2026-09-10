defmodule Jido.AI.Reasoning.TreeOfThoughts.Strategy do
  @moduledoc "Legacy result getters. Select ToT through an AI profile for core Flow execution."
  @deprecated "Use Jido.AI.Reasoning.TreeOfThoughts.get_nodes/1"
  defdelegate get_nodes(agent), to: Jido.AI.Reasoning.TreeOfThoughts
  @deprecated "Use Jido.AI.Reasoning.TreeOfThoughts.get_solution_path/1"
  defdelegate get_solution_path(agent), to: Jido.AI.Reasoning.TreeOfThoughts
  @deprecated "Use Jido.AI.Reasoning.TreeOfThoughts.get_result/1"
  defdelegate get_result(agent), to: Jido.AI.Reasoning.TreeOfThoughts
  @deprecated "Use Jido.AI.Reasoning.TreeOfThoughts.get_best_node/1"
  defdelegate get_best_node(agent), to: Jido.AI.Reasoning.TreeOfThoughts
end
