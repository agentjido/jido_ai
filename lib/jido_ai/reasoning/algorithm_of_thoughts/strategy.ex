defmodule Jido.AI.Reasoning.AlgorithmOfThoughts.Strategy do
  @moduledoc "Legacy result getter. Use the AoT method in an AI profile for core Agent/Flow execution."
  @deprecated "Use Jido.AI.Reasoning.AlgorithmOfThoughts.get_result/1"
  defdelegate get_result(agent), to: Jido.AI.Reasoning.AlgorithmOfThoughts
end
