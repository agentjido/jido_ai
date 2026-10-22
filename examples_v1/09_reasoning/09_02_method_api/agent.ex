defmodule JidoAI.Examples.MethodAPI do
  @moduledoc "Two linear methods selected through their public namespace APIs."
  alias Jido.AI.Authoring
  alias Jido.AI.Reasoning.ChainOfThought
  alias Jido.AI.Reasoning.ChainOfDraft

  def definition do
    profiles =
      for {id, namespace} <- [cot: ChainOfThought, cod: ChainOfDraft] do
        %{
          id: id,
          models: %{answer: %{model: JidoAI.Examples.MockLLM.model()}},
          reasoning: %{method: namespace.method(), model: :answer},
          result: %{schema: nil, into: :reply}
        }
      end

    Authoring.lower(
      %{
        name: "method_api",
        schema: Zoi.object(%{reply: Zoi.any() |> Zoi.default(nil)}),
        routes: [{"ai.cot.query", Authoring.ai(:cot)}, {"ai.cod.query", Authoring.ai(:cod)}]
      },
      profiles
    )
  end
end
