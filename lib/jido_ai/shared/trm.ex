defmodule Jido.AI.Reasoning.TRM do
  @moduledoc "TRM method selection and inspection of retained request data."
  alias Jido.AI.Reasoning.Linear
  alias Jido.AI.Reasoning.TRM.{Machine, Reasoning, Strategy, Supervision}

  def method, do: :trm

  @deprecated "Use method/0 for profile selection and namespace getters for retained requests"
  def strategy_module, do: Strategy

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

  def get_current_answer(%Jido.Agent{} = agent, request_id \\ nil),
    do: machine(agent, request_id).current_answer

  def get_confidence(%Jido.Agent{} = agent, request_id \\ nil),
    do: machine(agent, request_id).latent_state.confidence_score

  def get_supervision_step(%Jido.Agent{} = agent, request_id \\ nil),
    do: machine(agent, request_id).supervision_step

  def get_best_answer(%Jido.Agent{} = agent, request_id \\ nil),
    do: machine(agent, request_id).best_answer

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
