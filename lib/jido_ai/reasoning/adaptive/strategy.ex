defmodule Jido.AI.Reasoning.Adaptive.Strategy do
  @moduledoc "Deprecated analysis and inspection helpers. Agent, Flow and Session own execution."

  @deprecated "Use Jido.AI.Reasoning.Adaptive.analyze_prompt/2"
  defdelegate analyze_prompt(prompt, config \\ %{}), to: Jido.AI.Reasoning.Adaptive

  @deprecated "Use Jido.AI.Reasoning.Adaptive.get_selected_strategy/1"
  defdelegate get_selected_strategy(agent), to: Jido.AI.Reasoning.Adaptive

  @deprecated "Use Jido.AI.Reasoning.Adaptive.get_complexity_score/1"
  defdelegate get_complexity_score(agent), to: Jido.AI.Reasoning.Adaptive
end
