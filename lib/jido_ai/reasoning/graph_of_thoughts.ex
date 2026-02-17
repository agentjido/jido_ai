defmodule Jido.AI.Reasoning.GraphOfThoughts do
  @moduledoc """
  Canonical namespace entrypoint for Graph-of-Thoughts reasoning.

  This module exposes shared GoT helpers and points to the canonical strategy:
  `Jido.AI.Reasoning.GraphOfThoughts.Strategy`.
  """

  alias Jido.AI.Reasoning.GraphOfThoughts.Machine
  alias Jido.AI.Reasoning.GraphOfThoughts.Strategy

  @doc """
  Returns the canonical GoT strategy module.
  """
  @spec strategy_module() :: module()
  def strategy_module, do: Strategy

  @doc """
  Generates a unique GoT call ID.
  """
  @spec generate_call_id() :: String.t()
  defdelegate generate_call_id(), to: Machine

  @doc """
  Returns the default thought generation prompt.
  """
  @spec default_generation_prompt() :: String.t()
  defdelegate default_generation_prompt(), to: Machine

  @doc """
  Returns the default connection-finding prompt.
  """
  @spec default_connection_prompt() :: String.t()
  defdelegate default_connection_prompt(), to: Machine

  @doc """
  Returns the default aggregation prompt.
  """
  @spec default_aggregation_prompt() :: String.t()
  defdelegate default_aggregation_prompt(), to: Machine
end
