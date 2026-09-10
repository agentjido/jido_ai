defmodule Jido.AI.Reasoning.TreeOfThoughts do
  @moduledoc "ToT method selection and inspection of retained request results."
  alias Jido.AI.Reasoning.Linear
  alias Jido.AI.Reasoning.TreeOfThoughts.{Machine, Strategy}

  def method, do: :tree_of_thoughts

  @deprecated "Use method/0 for profile selection and namespace getters for retained requests"
  def strategy_module, do: Strategy

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

  def get_solution_path(%Jido.Agent{} = agent, request_id \\ nil),
    do: Map.get(search(agent, request_id), :solution_path, [])

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
