defmodule Jido.AI.Reasoning.TreeOfThoughts do
  @moduledoc "ToT method selection and inspection of retained request results."
  alias Jido.AI.Reasoning.Linear
  alias Jido.AI.Reasoning.TreeOfThoughts.Machine

  @doc "Returns the method ID stored with tree-of-thoughts requests."
  def method, do: :tree_of_thoughts

  defdelegate generate_call_id(), to: Machine
  defdelegate default_generation_prompt(), to: Machine
  defdelegate default_evaluation_prompt(), to: Machine

  @doc "Reads the latest retained ToT result, or a result with the given request ID."
  def get_result(%Jido.Agent{} = agent, request_id \\ nil) do
    case Linear.stored_record(agent, method(), request_id) do
      %{result: result} when is_map(result) -> result
      %{error: {:failed, _, result}} when is_map(result) -> result
      _ -> nil
    end
  end

  @doc "Reads retained nodes. Pending requests have no completed search snapshot."
  def get_nodes(%Jido.Agent{} = agent, request_id \\ nil),
    do: Map.get(search(agent, request_id), :nodes, %{})

  @doc "Reads the retained solution path for the selected request."
  def get_solution_path(%Jido.Agent{} = agent, request_id \\ nil),
    do: Map.get(search(agent, request_id), :solution_path, [])

  @doc "Finds the best retained leaf node, if one exists."
  def get_best_node(%Jido.Agent{} = agent, request_id \\ nil),
    do: Machine.find_best_leaf(Machine.from_map(%{nodes: get_nodes(agent, request_id)}))

  defp search(agent, request_id) do
    case Linear.stored_record(agent, method(), request_id) do
      %{meta: %{reasoning: %{method: :tree_of_thoughts} = reasoning}} -> reasoning
      %{error: {:failed, _, %{diagnostics: diagnostics}}} -> diagnostics
      _ -> %{}
    end
  end
end
