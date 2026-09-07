defmodule Jido.AI.Reasoning.ChainOfDraft.Strategy do
  @moduledoc """
  Legacy result getters over committed v3 request records.

  Use `Jido.AI.Reasoning.ChainOfDraft.method/0` in the AI profile and
  ordinary Agent routes for execution. Core v3 has no Agent Strategy callbacks.
  The old init/cmd/snapshot and worker action interfaces have been replaced by
  the shared Agent, Flow and Session APIs.
  """

  @deprecated "Use Jido.AI.Reasoning.ChainOfDraft.get_steps/1"
  defdelegate get_steps(agent), to: Jido.AI.Reasoning.ChainOfDraft

  @deprecated "Use Jido.AI.Reasoning.ChainOfDraft.get_conclusion/1"
  defdelegate get_conclusion(agent), to: Jido.AI.Reasoning.ChainOfDraft

  @deprecated "Use Jido.AI.Reasoning.ChainOfDraft.get_raw_response/1"
  defdelegate get_raw_response(agent), to: Jido.AI.Reasoning.ChainOfDraft
end
