defmodule Jido.AI.Reasoning.TreeOfThoughts do
  @moduledoc """
  Canonical namespace entrypoint for Tree-of-Thoughts reasoning.

  This module exposes shared ToT helpers and points to the canonical strategy:
  `Jido.AI.Reasoning.TreeOfThoughts.Strategy`.
  """

  alias Jido.AI.Reasoning.TreeOfThoughts.Machine
  alias Jido.AI.Reasoning.TreeOfThoughts.Strategy

  @doc """
  Returns the canonical ToT strategy module.
  """
  @spec strategy_module() :: module()
  def strategy_module, do: Strategy

  @doc """
  Generates a unique ToT call ID.
  """
  @spec generate_call_id() :: String.t()
  defdelegate generate_call_id(), to: Machine

  @doc """
  Returns the default thought generation prompt.
  """
  @spec default_generation_prompt() :: String.t()
  defdelegate default_generation_prompt(), to: Machine

  @doc """
  Returns the default thought evaluation prompt.
  """
  @spec default_evaluation_prompt() :: String.t()
  defdelegate default_evaluation_prompt(), to: Machine
end
