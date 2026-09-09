defmodule Jido.AI.Reasoning.TreeSearch do
  @moduledoc false
  alias Jido.AI.{Profile, Reasoning}
  alias Jido.AI.Reasoning.TreeOfThoughts.{Machine, Result}

  @defaults %{
    branching_factor: 3,
    max_depth: 3,
    traversal_strategy: :best_first,
    top_k: 3,
    min_depth: 2,
    max_nodes: 100,
    max_duration_ms: nil,
    beam_width: nil,
    early_success_threshold: 1.0,
    convergence_window: 2,
    min_score_improvement: 0.02,
    max_parse_retries: 1,
    max_tool_round_trips: 3,
    generation_prompt: nil,
    evaluation_prompt: nil
  }

  def options(value) do
    with {:ok, value} <- Profile.fields(value, Map.keys(@defaults), "reasoning.options"),
         options = Map.merge(@defaults, value),
         true <- options.traversal_strategy in [:bfs, :dfs, :best_first],
         true <-
           Enum.all?(
             [
               :branching_factor,
               :max_depth,
               :top_k,
               :max_nodes,
               :convergence_window,
               :max_tool_round_trips
             ],
             &(is_integer(options[&1]) and options[&1] > 0)
           ),
         true <-
           Enum.all?(
             [:min_depth, :max_parse_retries],
             &(is_integer(options[&1]) and options[&1] >= 0)
           ),
         true <- Enum.all?([:max_duration_ms, :beam_width], &optional_positive?(options[&1])),
         true <- score?(options.early_success_threshold),
         true <- is_number(options.min_score_improvement) and options.min_score_improvement >= 0,
         true <- Enum.all?([:generation_prompt, :evaluation_prompt], &optional_text?(options[&1])) do
      {:ok, options}
    else
      false -> Profile.error("reasoning.options", "Invalid Tree of Thoughts search options")
      error -> error
    end
  end

  def prepare(state, query) when is_binary(query) do
    options = state.profile.reasoning.options
    machine = Machine.new([emit_telemetry?: false] ++ Enum.to_list(options))

    {machine, work} =
      Machine.update(machine, {:start, query, Machine.generate_call_id()}, env(state))

    state =
      Map.put(state, :tree_search, %{machine: machine, tool_rounds: %{}, parser_repair?: false})

    if options.max_nodes == 1,
      do: {:error, failure(state, :max_nodes)},
      else: next(state, machine, work)
  end

  def prepare(_, _),
    do: Profile.error("query", "Tree of Thoughts currently requires a text query")

  def advance(%{tree_search: %{machine: %{status: "completed"}}} = state),
    do: {:done, state}

  def advance(state) do
    # The common request path counts every response, including tool follow-ups.
    # The search model receives no second copy of that usage.
    machine = %{state.tree_search.machine | usage: state.usage}
    value = %{text: response_text(state.response), usage: %{}}

    {machine, work} =
      Machine.update(machine, {:llm_result, machine.current_call_id, {:ok, value}}, env(state))

    case next(state, machine, work) do
      {:ok, %{tree_search: %{machine: %{status: "completed"}}}} = result ->
        {:done, elem(result, 1)}

      {:ok, state} ->
        {:continue, state}

      error ->
        error
    end
  end

  def tool_round(state) do
    search = state.tree_search
    id = search.machine.current_call_id
    count = Map.get(search.tool_rounds, id, 0)

    cond do
      search.parser_repair? ->
        {:error, {:unexpected_tool_calls, :tree_parse_repair}}

      count >= state.profile.reasoning.options.max_tool_round_trips ->
        {:error, {:max_tool_round_trips, phase(state)}}

      true ->
        {:ok,
         %{
           state
           | tree_search: %{search | tool_rounds: Map.put(search.tool_rounds, id, count + 1)}
         }}
    end
  end

  def event(state),
    do: %{reasoning_phase: phase(state), phase_call_id: state.tree_search.machine.current_call_id}

  def parse(state, _value) do
    machine = state.tree_search.machine
    result = result(state, machine)

    {:ok, result,
     %{
       termination_reason: machine.termination_reason,
       reasoning: %{
         method: :tree_of_thoughts,
         result: result,
         nodes: machine.nodes,
         solution_path: machine.solution_path
       }
     }}
  end

  def failure(_state, {:failed, _, %{tree: _}} = reason), do: reason

  def failure(state, reason) do
    machine = %{state.tree_search.machine | status: "error", termination_reason: :error}
    result = result(state, machine)

    result =
      result
      |> put_in([:diagnostics, :error], inspect(reason))
      |> put_in([:diagnostics, :cause], reason)
      |> put_in([:diagnostics, :nodes], machine.nodes)
      |> put_in([:diagnostics, :solution_path], machine.solution_path)

    {:failed, reason, result}
  end

  defp response_text(response) do
    case Reasoning.raw(response) do
      "" when is_map(response.object) or is_list(response.object) ->
        Jason.encode!(response.object)

      text ->
        text
    end
  end

  defp next(state, machine, work) do
    state = put_in(state.tree_search.machine, machine)

    case {machine.status, work} do
      {"completed", []} ->
        {:ok, state}

      {"error", []} ->
        reason = get_in(machine.result, [:diagnostics, :cause]) || :tree_search_failed
        {:error, failure(state, reason)}

      {_, [{:generate_thoughts, _, messages, _}]} ->
        messages(state, messages, false)

      {_, [{:evaluate_thoughts, _, thoughts}]} ->
        messages(state, evaluation_context(thoughts, env(state)), false)

      {_, [{:call_llm_stream, _, messages}]} ->
        messages(state, messages, true)

      _ ->
        {:error, failure(state, :invalid_tree_search_transition)}
    end
  end

  defp messages(state, messages, repair?) do
    with {:ok, messages} <- ReqLLM.Context.normalize(messages) do
      {:ok, %{state | messages: messages, tree_search: %{state.tree_search | parser_repair?: repair?}}}
    end
  end

  defp evaluation_context(thoughts, env) do
    text =
      thoughts
      |> Enum.with_index(1)
      |> Enum.map_join("\n", fn {entry, index} ->
        "#{index}. #{entry.id}: #{entry.content}"
      end)

    [
      %{role: :system, content: env.evaluation_prompt},
      %{role: :user, content: "Evaluate these thought approaches:\n\n#{text}"}
    ]
  end

  defp env(state) do
    options = state.profile.reasoning.options

    %{
      generation_prompt:
        options.generation_prompt || state.profile.instructions ||
          Machine.default_generation_prompt(),
      evaluation_prompt: options.evaluation_prompt || Machine.default_evaluation_prompt()
    }
  end

  defp result(state, machine) do
    # Rebuild the envelope so it contains the final common usage and tool rounds.
    diagnostics =
      if machine.result, do: machine.result.diagnostics, else: Machine.diagnostics(machine, nil)

    diagnostics = Map.put(diagnostics, :tool_rounds, state.tree_search.tool_rounds)
    Result.build(%{machine | usage: state.usage}, diagnostics: diagnostics)
  end

  defp phase(%{tree_search: %{machine: %{status: "generating"}}}), do: :generation
  defp phase(%{tree_search: %{machine: %{status: "evaluating"}}}), do: :evaluation
  defp phase(_), do: :completed
  defp optional_positive?(nil), do: true
  defp optional_positive?(n), do: is_integer(n) and n > 0
  defp optional_text?(nil), do: true
  defp optional_text?(value), do: is_binary(value)
  defp score?(value), do: is_number(value) and value >= 0 and value <= 1
end
