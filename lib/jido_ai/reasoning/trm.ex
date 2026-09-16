defmodule Jido.AI.Reasoning.TRM do
  @moduledoc "TRM method selection and inspection of retained request data."
  alias Jido.AI.Reasoning.Linear
  alias Jido.AI.Reasoning.TRM.{Machine, Reasoning, Supervision}

  @doc "Returns the method ID stored with TRM requests."
  def method, do: :trm

  defdelegate generate_call_id(), to: Machine
  defdelegate default_reasoning_prompt(), to: Reasoning, as: :default_reasoning_system_prompt

  defdelegate default_supervision_prompt(),
    to: Supervision,
    as: :default_supervision_system_prompt

  defdelegate default_improvement_prompt(),
    to: Supervision,
    as: :default_improvement_system_prompt

  @doc "Reads completed or failed method data. Pending requests have no retained phase data."
  def get_answer_history(%Jido.Agent{} = agent, request_id \\ nil),
    do: machine(agent, request_id).answer_history

  @doc "Reads the most recent answer retained for the selected request."
  def get_current_answer(%Jido.Agent{} = agent, request_id \\ nil),
    do: machine(agent, request_id).current_answer

  @doc "Reads the retained confidence score for the current answer."
  def get_confidence(%Jido.Agent{} = agent, request_id \\ nil),
    do: machine(agent, request_id).latent_state.confidence_score

  @doc "Reads the retained supervision step."
  def get_supervision_step(%Jido.Agent{} = agent, request_id \\ nil),
    do: machine(agent, request_id).supervision_step

  @doc "Reads the best answer retained across the request's steps."
  def get_best_answer(%Jido.Agent{} = agent, request_id \\ nil),
    do: machine(agent, request_id).best_answer

  @doc "Reads the retained score for the best answer."
  def get_best_score(%Jido.Agent{} = agent, request_id \\ nil),
    do: machine(agent, request_id).best_score

  defp machine(agent, request_id) do
    data =
      case Linear.stored_record(agent, method(), request_id) do
        %{meta: %{reasoning: %{method: :trm, trm: data}}} -> data
        %{error: {:failed, _, %{trm: data}}} -> data
        _ -> %{}
      end

    Machine.from_map(data)
  end
end
