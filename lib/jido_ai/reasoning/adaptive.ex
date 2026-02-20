defmodule Jido.AI.Reasoning.Adaptive do
  @moduledoc """
  Canonical namespace entrypoint for adaptive reasoning selection.

  This module exposes shared Adaptive helpers and points to the canonical strategy:
  `Jido.AI.Reasoning.Adaptive.Strategy`.
  """

  alias Jido.AI.Reasoning.Adaptive.Strategy

  @doc """
  Returns the canonical Adaptive strategy module.
  """
  @spec strategy_module() :: module()
  def strategy_module, do: Strategy

  @doc """
  Analyzes a prompt and returns the selected strategy metadata.
  """
  @spec analyze_prompt(String.t(), map()) :: {atom(), float(), atom()}
  defdelegate analyze_prompt(prompt, config \\ %{}), to: Strategy
end
