defmodule Jido.AI.Reasoning.GraphSearch do
  @moduledoc false
  alias Jido.AI.Profile
  alias Jido.AI.Reasoning
  alias Jido.AI.Reasoning.GraphOfThoughts.Machine

  @defaults %{
    max_nodes: 20,
    max_depth: 5,
    aggregation_strategy: :synthesis,
    min_nodes_for_aggregation: 3,
    generation_prompt: nil,
    connection_prompt: nil,
    aggregation_prompt: nil
  }

  def options(value) do
    with {:ok, value} <- Profile.fields(value, Map.keys(@defaults), "reasoning.options"),
         options = Map.merge(@defaults, value),
         true <- options.aggregation_strategy in [:synthesis, :voting, :weighted],
         true <-
           Enum.all?(
             [:max_nodes, :max_depth, :min_nodes_for_aggregation],
             &(is_integer(options[&1]) and options[&1] > 0)
           ),
         true <-
           Enum.all?(
             [:generation_prompt, :connection_prompt, :aggregation_prompt],
             &(is_nil(options[&1]) or is_binary(options[&1]))
           ) do
      {:ok, options}
    else
      false -> Profile.error("reasoning.options", "Invalid Graph of Thoughts search options")
      error -> error
    end
  end

  def prepare(state, query) when is_binary(query) do
    machine =
      Machine.new([emit_telemetry?: false] ++ Enum.to_list(state.profile.reasoning.options))

    {machine, work} =
      Machine.update(machine, {:start, query, Machine.generate_call_id()}, env(state))

    state = Map.put(state, :graph_search, machine)

    if machine.max_nodes == 1,
      do: {:error, failure(state, :max_nodes)},
      else: next(state, machine, work)
  end

  def prepare(_, _),
    do: Profile.error("query", "Graph of Thoughts currently requires a text query")

  def advance(%{graph_search: %{status: "completed"}} = state), do: {:done, state}

  def advance(state) do
    machine = %{state.graph_search | usage: state.usage}
    value = %{text: response_text(state.response), usage: %{}}

    {machine, work} =
      Machine.update(machine, {:llm_result, machine.current_call_id, {:ok, value}}, env(state))

    case next(state, machine, work) do
      {:ok, %{graph_search: %{status: "completed"}} = state} -> {:done, state}
      {:ok, state} -> {:continue, state}
      error -> error
    end
  end

  def event(state),
    do: %{
      reasoning_phase: phase(state.graph_search.status),
      phase_call_id: state.graph_search.current_call_id
    }

  def parse(state, _value) do
    machine = %{state.graph_search | usage: state.usage}

    {:ok, machine.result,
     %{
       termination_reason: machine.termination_reason,
       reasoning: %{method: :graph_of_thoughts, graph: Machine.to_map(machine)}
     }}
  end

  def failure(_state, {:failed, _, %{graph: _}} = reason), do: reason

  def failure(state, reason) do
    machine = %{
      state.graph_search
      | usage: state.usage,
        status: "error",
        termination_reason: :error
    }

    {:failed, reason,
     %{
       result: machine.result,
       graph: Machine.to_map(machine),
       usage: state.usage,
       termination: %{reason: :error, status: :error},
       diagnostics: %{cause: reason}
     }}
  end

  defp next(state, machine, work) do
    state = %{state | graph_search: machine}

    case {machine.status, work} do
      {"completed", [{:completed, _}]} -> {:ok, state}
      {"error", []} -> {:error, failure(state, machine.result)}
      {_, [{:generate_thought, _, context}]} -> messages(state, :generation, context)
      {_, [{:find_connections, _, _, context}]} -> messages(state, :connection, context)
      {_, [{:aggregate, _, _, context}]} -> messages(state, :aggregation, context)
      _ -> {:error, failure(state, :invalid_graph_search_transition)}
    end
  end

  defp messages(state, phase, context) do
    options = state.profile.reasoning.options

    system =
      case phase do
        :generation ->
          options.generation_prompt || state.profile.instructions || context.system_prompt

        :connection ->
          options.connection_prompt || context.system_prompt

        :aggregation ->
          options.aggregation_prompt || context.system_prompt
      end

    with {:ok, messages} <-
           ReqLLM.Context.normalize([
             %{role: :system, content: system},
             %{role: :user, content: user(phase, context)}
           ]),
         do: {:ok, %{state | messages: messages}}
  end

  defp user(:generation, %{context: previous} = context) when previous != "" do
    """
    Original problem: #{context.prompt}

    Previous reasoning:
    #{previous}

    Current thought to expand:
    #{context.current_thought}

    Please continue the reasoning from this point.
    """
  end

  defp user(:generation, context) do
    """
    Problem: #{context.prompt}

    #{context.current_thought}

    Please analyze this and provide your reasoning.
    """
  end

  defp user(:connection, context) do
    """
    Here are the thoughts in the graph:

    #{context.nodes}

    Identify meaningful connections between these thoughts.
    Format each connection as: CONNECTION: [node_id] -> [node_id] : [relationship]
    """
  end

  defp user(:aggregation, context) do
    """
    Original problem: #{context.prompt}

    Here are the thoughts to synthesize:

    #{context.thoughts}

    Please synthesize these into a coherent conclusion.
    """
  end

  defp env(state), do: Map.take(state.profile.reasoning.options, [:min_nodes_for_aggregation])

  defp response_text(response) do
    case Reasoning.raw(response) do
      "" when is_map(response.object) or is_list(response.object) ->
        Jason.encode!(response.object)

      text ->
        text
    end
  end

  defp phase("generating"), do: :generation
  defp phase("connecting"), do: :connection
  defp phase("aggregating"), do: :aggregation
  defp phase(_), do: :complete
end
