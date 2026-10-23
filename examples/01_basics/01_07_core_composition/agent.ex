defmodule JidoAI.Examples.CoreComposition.Audit do
  @moduledoc "A second stateless Agent extension."
  use Jido.Agent.Extension, id: "examples.audit"
end

defmodule JidoAI.Examples.CoreComposition.Agent do
  @moduledoc "Core Agent data and AI response data in one definition."

  use Jido.AI.Agent,
    name: "core_composition_example",
    extensions: [JidoAI.Examples.CoreComposition.Audit]

  state do
    schema Zoi.object(%{
             customer_id: Zoi.string(),
             request_count: Zoi.integer() |> Zoi.default(0)
           })
  end

  ai do
    model :fast
    instructions "Answer a customer question."
  end
end
