defmodule Jido.AI.Reasoning.ChainOfDraft do
  @moduledoc """
  Canonical namespace entrypoint for Chain-of-Draft reasoning.

  This module exposes shared CoD helpers and points to the canonical strategy:
  `Jido.AI.Reasoning.ChainOfDraft.Strategy`.
  """

  alias Jido.AI.Reasoning.ChainOfDraft.Strategy
  alias Jido.AI.Reasoning.ChainOfThought

  @doc """
  Returns the canonical CoD strategy module.
  """
  @spec strategy_module() :: module()
  def strategy_module, do: Strategy

  @doc """
  Returns the default CoD system prompt.
  """
  @spec default_system_prompt() :: String.t()
  def default_system_prompt do
    """
    You are a helpful AI assistant using Chain-of-Draft reasoning.

    Think step by step, but keep each intermediate draft extremely concise:
    - Use minimal draft steps with at most 5 words when possible.
    - Keep only the essential information needed to progress.
    - Avoid verbose explanations during reasoning.

    At the end of your response, provide the final answer after the separator ####.
    """
  end

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
  @spec extract_steps_and_conclusion(term()) :: {[Jido.AI.Reasoning.ChainOfThought.Machine.step()], String.t() | nil}
  defdelegate extract_steps_and_conclusion(text), to: ChainOfThought
end
