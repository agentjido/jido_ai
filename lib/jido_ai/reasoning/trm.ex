defmodule Jido.AI.Reasoning.TRM do
  @moduledoc """
  Canonical namespace entrypoint for Tiny-Recursive-Model reasoning.

  This module exposes shared TRM helpers and points to the canonical strategy:
  `Jido.AI.Reasoning.TRM.Strategy`.
  """

  alias Jido.AI.Reasoning.TRM.Machine
  alias Jido.AI.Reasoning.TRM.Strategy

  @doc """
  Returns the canonical TRM strategy module.
  """
  @spec strategy_module() :: module()
  def strategy_module, do: Strategy

  @doc """
  Generates a unique TRM call ID.
  """
  @spec generate_call_id() :: String.t()
  defdelegate generate_call_id(), to: Machine

  @doc """
  Returns the default reasoning system prompt.
  """
  @spec default_reasoning_prompt() :: String.t()
  defdelegate default_reasoning_prompt(), to: Strategy

  @doc """
  Returns the default supervision system prompt.
  """
  @spec default_supervision_prompt() :: String.t()
  defdelegate default_supervision_prompt(), to: Strategy

  @doc """
  Returns the default improvement system prompt.
  """
  @spec default_improvement_prompt() :: String.t()
  defdelegate default_improvement_prompt(), to: Strategy
end
