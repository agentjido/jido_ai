defmodule Jido.AI.Reasoning.GraphOfThoughts do
  @moduledoc "GoT method selection and inspection of retained request graphs."
  alias Jido.AI.Reasoning.Linear
  alias Jido.AI.Reasoning.GraphOfThoughts.Machine

  @doc "Returns the method ID stored with graph-of-thoughts requests."
  def method, do: :graph_of_thoughts

  defdelegate generate_call_id(), to: Machine
  defdelegate default_generation_prompt(), to: Machine
  defdelegate default_connection_prompt(), to: Machine
  defdelegate default_aggregation_prompt(), to: Machine

  @doc "Reads a retained result. Failed requests expose the original error cause."
  def get_result(%Jido.Agent{} = agent, request_id \\ nil) do
    case Linear.stored_record(agent, method(), request_id) do
      %{status: :completed, result: result} -> result
      %{status: :failed, error: {:failed, reason, _}} -> {:error, reason}
      %{status: :failed, error: reason} -> {:error, reason}
      _ -> nil
    end
  end

  @doc "Reads retained graph nodes as a list. Pending requests have no retained graph."
  def get_nodes(%Jido.Agent{} = agent, request_id \\ nil),
    do: agent |> machine(request_id) |> Machine.get_nodes()

  @doc "Reads retained graph edges for the selected request."
  def get_edges(%Jido.Agent{} = agent, request_id \\ nil),
    do: machine(agent, request_id).edges

  @doc "Finds the best retained leaf node, if one exists."
  def get_best_node(%Jido.Agent{} = agent, request_id \\ nil),
    do: agent |> machine(request_id) |> Machine.find_best_leaf()

  @doc "Traces the retained path to the best leaf node."
  def get_solution_path(%Jido.Agent{} = agent, request_id \\ nil) do
    machine = machine(agent, request_id)

    case Machine.find_best_leaf(machine) do
      nil -> []
      best -> Machine.trace_path(machine, best.id)
    end
  end

  defp machine(agent, request_id) do
    graph =
      case Linear.stored_record(agent, method(), request_id) do
        %{meta: %{reasoning: %{method: :graph_of_thoughts, graph: graph}}} -> graph
        %{error: {:failed, _, %{graph: graph}}} -> graph
        _ -> %{}
      end

    Machine.from_map(graph)
  end
end
