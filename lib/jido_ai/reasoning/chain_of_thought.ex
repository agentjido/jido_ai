defmodule Jido.AI.Reasoning.ChainOfThought do
  @moduledoc """
  CoT method selection, prompts and stored result inspection.

  Use `method/0` in a v3 AI profile. Core Agent and Flow own execution.
  Legacy Strategy modules retain result getters only.
  """

  alias Jido.AI.Reasoning.Linear
  alias Jido.AI.Reasoning.ChainOfThought.Strategy

  @doc """
  Returns the legacy result-inspection module. It is not a v3 executor.
  """
  @deprecated "Use method/0 for AI profile selection and namespace result getters for inspection"
  @spec strategy_module() :: module()
  def strategy_module, do: Strategy

  @doc "Returns the method value accepted by the shared AI profile."
  def method, do: :chain_of_thought

  @doc "Returns stored steps for a request, or the latest request of this method."
  def get_steps(agent, request_id \\ nil),
    do: Jido.AI.Reasoning.Linear.stored_reasoning(agent, method(), request_id)[:steps] || []

  @doc "Returns the stored conclusion for a request of this method."
  def get_conclusion(agent, request_id \\ nil),
    do: Jido.AI.Reasoning.Linear.stored_reasoning(agent, method(), request_id)[:conclusion]

  @doc "Returns the stored raw model text for a request of this method."
  def get_raw_response(agent, request_id \\ nil),
    do: Jido.AI.Reasoning.Linear.stored_reasoning(agent, method(), request_id)[:raw_response]

  @doc """
  Returns the default CoT system prompt.
  """
  @spec default_system_prompt() :: String.t()
  def default_system_prompt, do: Linear.default_prompt(:chain_of_thought)

  @doc """
  Generates a unique CoT call ID.
  """
  @spec generate_call_id() :: String.t()
  def generate_call_id, do: "cot_#{Jido.Util.generate_id()}"

  @doc """
  Extracts structured steps and conclusion from CoT output text.
  """
  @spec extract_steps_and_conclusion(term()) :: {[Linear.step()], String.t() | nil}
  defdelegate extract_steps_and_conclusion(text), to: Linear
end
