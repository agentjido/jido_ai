defmodule Jido.AI.Reasoning.ChainOfThought do
  @moduledoc """
  Canonical namespace entrypoint for Chain-of-Thought reasoning.

  This module exposes shared CoT helpers and points to the canonical strategy:
  `Jido.AI.Reasoning.ChainOfThought.Strategy`.
  """

  alias Jido.AI.Reasoning.ChainOfThought.Machine
  alias Jido.AI.Reasoning.ChainOfThought.Strategy

  @doc """
  Returns the canonical CoT strategy module.
  """
  @spec strategy_module() :: module()
  def strategy_module, do: Strategy

  @doc """
  Returns the default CoT system prompt.
  """
  @spec default_system_prompt() :: String.t()
  defdelegate default_system_prompt(), to: Machine

  @doc """
  Generates a unique CoT call ID.
  """
  @spec generate_call_id() :: String.t()
  defdelegate generate_call_id(), to: Machine

  @doc """
  Extracts structured steps and conclusion from CoT output text.
  """
  @spec extract_steps_and_conclusion(term()) :: {[Machine.step()], String.t() | nil}
  defdelegate extract_steps_and_conclusion(text), to: Machine
end
