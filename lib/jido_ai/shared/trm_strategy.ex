defmodule Jido.AI.Reasoning.TRM.Strategy do
  @moduledoc """
  Deprecated inspection and prompt helpers for TRM.

  Core Agent routes, Flow and the shared Session replace Strategy execution.
  This module owns no commands, process, model call or request state.
  """

  @deprecated "Use Jido.AI.Reasoning.TRM.get_answer_history/1"
  defdelegate get_answer_history(agent), to: Jido.AI.Reasoning.TRM

  @deprecated "Use Jido.AI.Reasoning.TRM.get_current_answer/1"
  defdelegate get_current_answer(agent), to: Jido.AI.Reasoning.TRM

  @deprecated "Use Jido.AI.Reasoning.TRM.get_confidence/1"
  defdelegate get_confidence(agent), to: Jido.AI.Reasoning.TRM

  @deprecated "Use Jido.AI.Reasoning.TRM.get_supervision_step/1"
  defdelegate get_supervision_step(agent), to: Jido.AI.Reasoning.TRM

  @deprecated "Use Jido.AI.Reasoning.TRM.get_best_answer/1"
  defdelegate get_best_answer(agent), to: Jido.AI.Reasoning.TRM

  @deprecated "Use Jido.AI.Reasoning.TRM.get_best_score/1"
  defdelegate get_best_score(agent), to: Jido.AI.Reasoning.TRM

  @deprecated "Use Jido.AI.Reasoning.TRM.default_reasoning_prompt/0"
  defdelegate default_reasoning_prompt(), to: Jido.AI.Reasoning.TRM

  @deprecated "Use Jido.AI.Reasoning.TRM.default_supervision_prompt/0"
  defdelegate default_supervision_prompt(), to: Jido.AI.Reasoning.TRM

  @deprecated "Use Jido.AI.Reasoning.TRM.default_improvement_prompt/0"
  defdelegate default_improvement_prompt(), to: Jido.AI.Reasoning.TRM
end
