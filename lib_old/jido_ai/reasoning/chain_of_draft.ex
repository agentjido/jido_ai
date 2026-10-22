defmodule Jido.AI.Reasoning.ChainOfDraft do
  @moduledoc """
  CoD method selection, prompts and stored result inspection.

  Use `method/0` in a v3 AI profile. Core Agent and Flow own execution.
  The method namespace provides result inspection.
  """

  alias Jido.AI.Reasoning.ChainOfThought

  @doc "Returns the method value accepted by the shared AI profile."
  def method, do: :chain_of_draft

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
  Returns the default CoD system prompt.
  """
  @spec default_system_prompt() :: String.t()
  def default_system_prompt, do: Jido.AI.Reasoning.Linear.default_prompt(:chain_of_draft)

  @doc """
  Generates a unique CoD call ID.
  """
  @spec generate_call_id() :: String.t()
  def generate_call_id do
    "cod_#{Jido.Util.generate_id()}"
  end

  @doc """
  Extracts structured steps and conclusion from CoD output text.
  """
  @spec extract_steps_and_conclusion(term()) ::
          {[ChainOfThought.step()], String.t() | nil}
  defdelegate extract_steps_and_conclusion(text), to: ChainOfThought
end
