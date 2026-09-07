defmodule Jido.AI.Reasoning.Recursive do
  @moduledoc false
  alias Jido.AI.Profile
  alias Jido.AI.Reasoning.TRM.{Machine, Helpers, Reasoning, Supervision}

  @defaults %{max_supervision_steps: 5, act_threshold: 0.9}

  def options(value) do
    with {:ok, value} <- Profile.fields(value, Map.keys(@defaults), "reasoning.options"),
         options = Map.merge(@defaults, value),
         true <- is_integer(options.max_supervision_steps) and options.max_supervision_steps > 0,
         true <-
           is_number(options.act_threshold) and options.act_threshold >= 0 and
             options.act_threshold <= 1 do
      {:ok, options}
    else
      false ->
        Profile.error(
          "reasoning.options",
          "Expected positive TRM steps and a threshold from 0 to 1"
        )

      error ->
        error
    end
  end

  def prepare(state, query) when is_binary(query) do
    machine =
      Machine.new([emit_telemetry?: false] ++ Enum.to_list(state.profile.reasoning.options))

    {machine, work} = Machine.update(machine, {:start, query, Machine.generate_call_id()})
    next(Map.put(state, :recursive, machine), machine, work)
  end

  def prepare(_, _), do: Profile.error("query", "TRM currently requires a text query")

  def advance(%{recursive: %{status: "completed"}} = state), do: {:done, state}

  def advance(state) do
    machine = %{state.recursive | usage: state.usage}
    value = %{text: response_text(state.response), usage: %{}}
    message = {result_phase(machine.status), machine.current_call_id, {:ok, value}}
    {machine, work} = Machine.update(machine, message)

    case next(state, machine, work) do
      {:ok, %{recursive: %{status: "completed"}} = state} -> {:done, state}
      {:ok, state} -> {:continue, state}
      error -> error
    end
  end

  def event(state),
    do: %{
      reasoning_phase: phase(state.recursive.status),
      phase_call_id: state.recursive.current_call_id,
      supervision_step: state.recursive.supervision_step
    }

  def parse(state, _value) do
    machine = %{state.recursive | usage: state.usage}

    {:ok, machine.result,
     %{
       termination_reason: machine.termination_reason,
       reasoning: %{method: :trm, trm: Machine.to_map(machine)}
     }}
  end

  def failure(_state, {:failed, _, %{trm: _}} = reason), do: reason

  def failure(state, reason) do
    machine = %{
      state.recursive
      | usage: state.usage,
        status: "error",
        termination_reason: :error,
        result: state.recursive.result || Helpers.safe_error_message(reason)
    }

    {:failed, reason,
     %{
       result: machine.result,
       trm: Machine.to_map(machine),
       usage: state.usage,
       termination: %{reason: :error, status: :error},
       diagnostics: %{cause: reason, phase: phase(state.recursive.status)}
     }}
  end

  defp next(state, machine, work) do
    state = %{state | recursive: machine}

    case {machine.status, work} do
      {"completed", []} ->
        {:ok, state}

      {_, [{:reason, _, context}]} ->
        messages(state, Reasoning.build_reasoning_prompt(context))

      {_, [{:supervise, _, context}]} ->
        context = Map.put(context, :answer, context.current_answer)
        messages(state, Supervision.build_supervision_prompt(context))

      {_, [{:improve, _, context}]} ->
        messages(
          state,
          Supervision.build_improvement_prompt(
            context.question,
            context.current_answer,
            context.parsed_feedback
          )
        )

      _ ->
        {:error, failure(state, :invalid_recursive_transition)}
    end
  end

  defp messages(state, {system, user}) do
    # Keep each phase's required format when the profile supplies instructions.
    system = Enum.join(Enum.reject([state.profile.instructions, system], &is_nil/1), "\n\n")

    with {:ok, messages} <-
           ReqLLM.Context.normalize([
             %{role: :system, content: system},
             %{role: :user, content: user}
           ]),
         do: {:ok, %{state | messages: messages}}
  end

  defp response_text(response) do
    case Jido.AI.Reasoning.raw(response) do
      "" when is_map(response.object) or is_list(response.object) ->
        Jason.encode!(response.object)

      text ->
        text
    end
  end

  defp result_phase("reasoning"), do: :reasoning_result
  defp result_phase("supervising"), do: :supervision_result
  defp result_phase("improving"), do: :improvement_result
  defp phase("reasoning"), do: :reasoning
  defp phase("supervising"), do: :supervision
  defp phase("improving"), do: :improvement
  defp phase(_), do: :complete
end
