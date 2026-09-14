defmodule Jido.AI.Reasoning.Adaptive do
  @moduledoc "Adaptive method selection and inspection of retained requests."
  alias Jido.AI.Reasoning.{Linear, Adaptive.Selection}

  def method, do: :adaptive

  defdelegate analyze_prompt(prompt, config \\ %{}), to: Selection

  @doc "Reads the committed selection, including a pending request after method preparation."
  def get_selected_strategy(%Jido.Agent{} = agent, request_id \\ nil),
    do: selection(agent, request_id)[:strategy]

  def get_complexity_score(%Jido.Agent{} = agent, request_id \\ nil),
    do: selection(agent, request_id)[:complexity_score]

  defp selection(agent, request_id) do
    case Linear.stored_record(agent, method(), request_id) do
      %{meta: %{adaptive: selection}} ->
        selection

      _ ->
        %{}
    end
  end
end
